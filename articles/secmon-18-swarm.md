---
title: "実践セキュリティ監視基盤構築(18): ログ変換と書込の実装例"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の18日目です。

前回までで、セキュリティ監視基盤のデータ取り込みの基本的な流れであるログの変換と書込みについて説明しました。今回は、これらの処理を実際に実装した例を紹介します。

# ログ変換・書込ツール Swarm

改めて、ログ変換と書込の要件を簡単にまとめてみます。

- **ログ変換**
  - 柔軟なスキーマ変換のロジックが実装できるが、機能過多にならない
  - 変換のロジックをテストできる
- **ログ書込**
  - スキーマの自動更新ができる
  - ログ書込の遅延を制御できる（スケールアウトできるなど）
  - コストをなるべく抑える

詳細はこれまでの記事を参照していただくとして、これらの要件を満たすために今回は Swarm というツールを構築しています。

https://github.com/secmon-lab/swarm

![](https://storage.googleapis.com/zenn-user-upload/9f5f55b33cc2-20241208.jpg)

端的に言うと Swarm は Cloud Storage にオブジェクトが作成されたというイベントをPub/Sub経由で受信し、そのオブジェクトを取得してスキーマ変換を行い、BigQueryに書き込むだけのシンプルなツールです。スキーマ自動変更の実現とコストをなるべく抑えるという観点から、BigQueryにデータを書き込むのにはStorage Write APIが有力であるという解説を以前にしました。Storage Write APIによる書込は自前で実装する必要があるため、その実現の過程でSwarmは生まれました。

Swarmの最大の特徴は、スキーマ変換のロジックを[Rego](https://www.openpolicyagent.org/docs/latest/policy-language/)で実装していることです。Regoは[Open Policy Agent](https://www.openpolicyagent.org/)（OPA）のランタイム上で動くポリシー言語で、本来は認可制御を目的とした宣言型の言語なのです。しかしRegoの本質は「**構造型データを異なる構造型データへ変換する**」機能に特化した言語であり、これをスキーマの変換に応用したのが Swarm です。

RegoはGo言語のライブラリとして提供されており、Go言語のプログラムに容易に組み込むことができます。SwarmはこのRegoを利用して、Cloud Storageから取得したログをBigQueryに書き込む前にスキーマ変換を行います。Regoは[最低限の文字列変換や分岐、配列や構造データの処理機能](https://www.openpolicyagent.org/docs/latest/policy-reference/#built-in-functions)などを持ちますが、外部I/Oの機能をもたない[^ext-io]ため、スキーマ変換のロジックをシンプルに保つことができます。

[^ext-io]: 厳密にはHTTPリクエストを送信する機能がありますが、例外として扱っています。

# Swarm の特徴

## (1) Regoを利用した柔軟なスキーマ変換とテスト可能性の実現

まず1つ目の特徴は、先程も述べた通りRegoを使ってスキーマの変換をするという点です。より詳細に説明すると、Swarmは以下のような処理をRegoによって行います。

1. Cloud Storageから取得したオブジェクトをどのスキーマのログとして扱うかを決定する
2. そのログをBigQueryに書き込むためのスキーマに変換する
3. 変換したログを書き込む先のBigQueryデータセット、テーブルを決定する

### 取得したオブジェクトのスキーマ判定

順番に見ていきましょう。まず、Cloud Storageから取得したオブジェクトをどのスキーマのログとして扱うかを決定するために、Swarmは `event` というポリシーを参照します。具体的には以下のようにルールを記述します。

```rego
package event

src[s] {
	# ログのバケットやパス名からログの種類を判定する
	input.data.bucket == "swarm-test-bucket"
	starts_with(input.data.name, "logs/")
	ends_with(input.data.name, ".log.gz")

	# ログの種類や処理方法を決定する
	s := {
		"parser": "json",
		"schema": "github_audit",
		"compress": "gzip",
	}
}
```

Regoは記述方法が独特なので慣れない方には読みにくいかもしれませんが、`src[s] {` から始まるブロックが1つのルールになっており、上3行が条件、下5行が結果を返すための文となっています。このルールの条件部分が成立すると `s` に代入された構造体が `src` というセットに格納されて、これが評価結果になります。逆に条件が成立しないと `src` は空のセットになります。

このポリシーは、ログのバケットが `swarm-test-bucket` で、パス名が `logs/` で始まり `.log.gz` で終わるオブジェクトを `github_audit` というスキーマのログとして扱う、という意味です。 `input.data` は[Cloud Storageから受け取ったイベントのメッセージ](https://cloud.google.com/storage/docs/json_api/v1/objects#resource-representations)がそのまま格納されている構造体で、この中にバケット名やパス名などの情報が含まれています。

条件が満たされると、 `parser`, `schema`, `compress` という3つのキーを持つ構造体が `s` に代入されます。概ね予想がつく通り、 `parser` はオブジェクトデータのパース方法、 `schema` はログのスキーマ、 `compress` はオブジェクトデータの圧縮方法を示しています。 `schema` は後述するスキーマ変換の際にどのルールを適用するかを決定するために使われます。

### スキーマ変換

次に、取得したログをBigQueryに書き込むためのスキーマに変換する処理をRegoで行います。この処理は `schema.<スキーマ名>` というポリシーを参照します。`<スキーマ名>` が先程の `event` ルールの返り値で指定した `schema` になります。そのため今回の例では `schema.github_audit` というポリシーが利用されます。

```rego
package schema.github_audit

log[d] {
	d := {
		"dataset": "my_log_dataset",
		"table": "my_github_audit",

		"id": input._document_id,
		"timestamp": input["@timestamp"] / 1000,
		"data": json.patch(input, [{"op": "remove", "path": "/@timestamp"}]),
	}
}
```

こちらのルールは条件はなく、返り値のみが設定されています。 `d` という変数に代入された構造体が `log` というセットに格納されます。構造体の各フィールドは以下のような意味を持ちます。

- ログの書込先を決定するフィールド
  - `dataset`: BigQueryのデータセットを指定
  - `table`: BigQueryのテーブルを指定
- ログそのものを示すフィールド
  - `id`: （提供元スコープでの）ログの一意性を示すID
  - `timestamp`: ログの発生時刻（Unix timestamp、秒単位）
  - `data`: 変換されたログデータを格納するフィールド

この構造体はログの1レコード単位で作成されます。そのため、この仕組みはログの書込先を1レコード単位で制御することができます。例えば同じオブジェクトに複数種類のログが混在しておりスキーマもバラバラの場合に、異なるテーブルに振り分けるといったことが可能になります。

ログのスキーマについてはデータベース設計のパートで例示した通り、重複排除のための `id` 、統一的にログの発生時刻を示すための `timestamp` 、そして変換後のログデータを格納する `data` となっており、これがBigQueryにそのまま書き込まれます。

このルールでログがどのように処理されるかを説明します。このログは[GitHub Audit Log](https://docs.github.com/en/enterprise-cloud@latest/admin/monitoring-activity-in-your-enterprise/reviewing-audit-logs-for-your-enterprise/audit-log-events-for-your-enterprise)を例として取り扱っています。(実際のスキーマは[こちら](https://docs.github.com/en/enterprise-cloud@latest/rest/enterprise-admin/audit-log)の "Example schema" や "Response schema" を参照してください) `input` にログの1レコードがそのまま格納されています。

- `id`: GitHub内におけるログの一意性を示すフィールドとして、GitHub Audit Logには `_document_id` というフィールドがあり、 "A unique identifier for an audit event." と説明されているため、これをそのまま流用するため `input._document_id` を指定しています。
- `timestamp`: GitHub Audit Logに `@timestamp` というフィールドがあり、 "The time the audit log event occurred, given as a [Unix timestamp](http://en.wikipedia.org/wiki/Unix_time)." と説明されているためこれを利用します。ただしGitHub Audit Logはミリ秒で記録されており、Swarm側は秒で扱いたいため、1000で割る処理を行った上で格納しています。
- `data`: その他のログデータはそのまま `input` に格納されているため、これをそのまま `data` に格納しています。ただし `@timestamp` は `timestamp` に移動しており、かつBigQueryは `@` の文字を含むフィールド名を許容していないため、 `@timestamp` を削除する処理を行っています。

これらの処理を経て、 `log` に格納されたデータがBigQueryに書き込まれることになります。

### テスト

要件においても触れましたが、こういったロジックを記述する場合はテストが必要であると考えられます。自分が記述したロジックが実際のデータにどの用に作用するのかを手元で試してからデプロイできたほうが手戻りも少なくすみます。

また、ごく少数のロジックを扱っているうちはいいですが、複数ロジックを扱い始めると見通しを良くするなどの目的でルールを統廃合したり整理するなどの構造化が必要になります。そうすると部分的な変更が別の場所に干渉するということも起こるため、回帰テストも必要です。

Rego + OPAでは標準的にテストの機能が備わっており、Swarmもそれを利用することを想定して設計されています。具体的には以下のようなデータとテストコードを用意します。

データ
```json:testdata/github_audit/data.json
{
  "@timestamp": 1606929874512,
  "action": "team.add_member",
  "actor": "octocat",
  "created_at": 1606929874512,
  "_document_id": "xJJFlFOhQ6b-5vaAFy9Rjw",
  "org": "octo-corp",
  "team": "octo-corp/example-team",
  "user": "monalisa"
}
```

テストコード
```rego:schema_test.rego
package schema.github_audit

test_parse {
	logs := log with input as data.testdata.github_audit

    # ログ件数の検証
	count(logs) == 1

    # ログの各フィールドの検証
    logs[x].id == "xJJFlFOhQ6b-5vaAFy9Rjw"
    logs[x].timestamp == 1606929874.512
    logs[x].data.user == "monalisa"

    # @timestamp フィールドがないことの検証
    not logs[x].data["@timestamp"]
}
```

データは実際に取得されるログをそのまま構造データとして設置すればよいです。テストコードは `test_` というプレフィックスを持つルールを作成することでOPAがテストとして認識するようになります。この処理では `testdata/github_audit/data.json` を `input` にそのまま代入して、 `log` というルールを評価した結果を検証します。Regoのテストについて詳しくは[こちらのドキュメント](https://www.openpolicyagent.org/docs/latest/policy-testing/)を御覧ください。

これを用意した後、 `opa` コマンドで以下のようにテストを実行できます。

```shell
% opa test -v .
schema_test.rego:
data.schema.github_audit.test_parse: PASS (677.625µs)
--------------------------------------------------------------------------------
PASS: 1/1
```

これを手元で実行したり、CIに組み込むことでログの変換ロジックが適切に動作することを検証したうえでデプロイすることが可能になります。

## (2) スキーマの自動更新

BigQueryに格納されるべきログが揃ったら、次はスキーマの更新をします。SwarmはBigQueryのスキーマを自動更新するために [bqs](https://github.com/m-mizutani/bqs) というBigQueryのスキーマを取り扱うライブラリを利用しています。

https://github.com/m-mizutani/bqs

このライブラリはGoの構造体やmap形式から、BigQueryの構造体データ (`bigquery.Schema`) を生成する機能を提供しています。Goの構造体からBigQueryのスキーマを生成する機能は公式SDKの [bigquery.InferSchema](https://pkg.go.dev/cloud.google.com/go/bigquery#InferSchema) でも提供されていますが、 **ネストした構造体やmap型のスキーマが生成できない** という制約があります。bqsはこの制約を解消し、ネストした構造体やmap型のスキーマも生成できるようになっています。さらにスキーマの比較やマージといった機能を備えています。

以下がスキーマ生成とマージの例です。
```go
// Row は map[string]any で bigquery.ValueSaver を実装しています
rows := []Row{
    {
        "CreatedAt": time.Now(),
        "Name":      "Alice",
        "Preferences": map[string]any{
            "Color": "Red",
        },
    },
    {
        "CreatedAt": time.Now(),
        "Name":      "Bob",
        "Age":       30,
    },
}

var mergedSchema bigquery.Schema
for _, row := range rows {
    // もしここで bigquery.InferSchema を使うと、ネストした構造体のスキーマが生成できずエラーになります
    schema, err := bqs.Infer(row)
    if err != nil {
        return err
    }

    // bqsは複数スキーマをマージする機能があり、これによってスキーマが不安定なログの集合であっても全てを書込可能なスキーマを生成できます
    mergedSchema, err = bqs.Merge(mergedSchema, schema)
    if err != nil {
        return err
    }
}
```

このようにして書き込もうとしているログを全て包含するスキーマを作成した後、BigQuery上のテーブルのスキーマも取得してマージします。マージした結果が現状から変化していなければ何もせず、変化があった場合のみテーブルのスキーマ更新を実施します。このような処理をすることで、自動的に書き込もうとしているログのスキーマにBigQueryテーブルのスキーマを追随させ、継続的にログが投入できるようになります。

https://github.com/secmon-lab/swarm/blob/80d4712dbb668c299c99f85b7402f80fbcb1c1e0/pkg/usecase/bigquery.go#L26-L34

この方法は便利ですが、2点ほど注意があります。

- ⚠️ **スキーマが衝突した場合は手動で対応する必要がある**: この仕組みで継続的な自動アップデートが実現されますが、フィールドの型が違うなどのようなケースはそもそもBigQueryの仕組み上サポートされていないので対応できません。その場合は自分でスキーマの差異を調査し、ログ変換のロジックを追加する必要があります。
- ⚠️ **スキーマ更新の適用完了には遅延がある**: 先述しましたが、BigQueryはスキーマ更新してからそれが浸透するまで[最大で10分程度かかる](https://issuetracker.google.com/issues/64329577?pli=1#comment3)とされています。そのためExponential backoffなどを使いつつ適切なリトライ機能を併せて実装する必要があります。スキーマが合致せず書込が失敗したことは、Goだと以下のようなコードで検知できます。

https://github.com/secmon-lab/swarm/blob/80d4712dbb668c299c99f85b7402f80fbcb1c1e0/pkg/infra/bq/writer/manager.go#L134-L143

## (3) Pub/SubのPull型subscriptionとCloud Run Jobを利用したスケールアウト

Swarmは Cloud Run **Job** と **Pull型**のPub/Sub Subscriptionを使って動作させています。一般的に「Cloud Storageのオブジェクト作成イベントを受け取って、オブジェクトを処理する」というユースケースの場合は **Push型**のPub/Sub SubscriptionとCloud Run **Service**という構成を想像されると思いますが、今回は以下の理由でPush型＋Cloud Run Serviceの構成を見送りました。

- ❌️ **スケールイン・アウトの戦略があわない**: [Cloud Run Serviceのオートスケーリングの戦略](https://cloud.google.com/run/docs/about-instance-autoscaling)は主にCPUの使用率を基準にします。これは一般的なWebアプリケーション（リクエストの時間が短く、メモリの消費も少ない）では良いのですが、ログの変換・書込処理ではメモリ使用量が多くブロッキングの時間が比較的長くなります。するとスケールアウトしてほしいときにいつまでもスケールアウトしないということが起こりやすくなります。またスケールインも比較的遅く、無駄にコストがかかってしまうこともありました。
- ❌️ **SubscriptionのAcknowledgment deadlineの最大値が短い**: Pub/SubのSubscriptionで設定できるAcknowledgment deadline（メッセージを受け取ってから処理完了のackを返すまでの時間）は[最大で600秒](https://cloud.google.com/pubsub/docs/subscription-properties#ack_deadline)です。これはおおむねのログ変換・書込処理において問題ない範囲ですが、それでも大量の書込が必要になった場合はブロッキングなどによりこの時間を超過する場合があります。Push型の場合はAcknowledgment deadlineを超えると処理が失敗したとみなしてメッセージを再送しますが、実際には前の処理が終わっていないため、処理の負荷をさらに増やすだけとなってしまいます。

この問題を解決するため、Swarmは **短い期間でCloud Run Jobを起動してPull型のSubscriptionをチェックし、メッセージが存在した場合のみ処理をする** という戦略にしました。このアーキテクチャは前述の問題を以下のように解決します。

- ✅️ **スケールアウト・インのコントロールがしやすい**: Cloud Run Jobは起動、終了を完全に開発者側で制御できます。そのため必要なくなったらすぐにJobを終了させることで無駄なコストを削ることができます。
- ✅️ **Acknowledgment deadlineを延長できる**: Pull型のSubscriptionに限って、[ModifyAckDeadline](https://cloud.google.com/pubsub/docs/reference/rest/v1/projects.subscriptions/modifyAckDeadline)というAPIを呼び出すことができます。これによって最大設定値の600秒を超えてメッセージを適切に処理できるようになり、同じメッセージに対する呼び出しが多重化しなくなります。

# Swarm のアーキテクチャ

ここまでの議論をもとに実際のSwarmのデプロイアーキテクチャを示したものが以下になります。

![](https://storage.googleapis.com/zenn-user-upload/8b2357471e49-20241208.jpg)

先述した通りSwarmはCloud Run Jobで動かすため、起動をCloud Scheduler + Workflowsにまかせています。このユースケースではCloud Schedularだけで起動してもほぼ問題ないのですが、平仄をあわせるためにWorkflowsも利用しています。

Pub/SubについてはCloud Storageごとに分けるべきか、それとも統一するべきかは検討の余地があります。図中ではCloud StorageごとにPub/Sub topic + subscriptionを用意していますが、全ての通知を一つのtopicに集約する構成でも実現可能です。検討するポイントとしては以下があります。

- 🤔 **subscriptionをチェックする時間**: Swarmではメッセージを一度に取得しすぎないように、複数のsubscriptionがあった場合でも直列でメッセージの有無をチェックします。その代わり、1つのsubscriptionのメッセージ有無チェックには数秒必要であり、これはsubscriptionの数に比例して増加します。Cloud Run Jobは起動時間によって課金されるため、課金が気になる場合は1つのsubscriptionに集約して起動時間を短縮することができます
- 🤔 **トラブル時の対応**: 例えばなんらかの理由である特定のCloud Storageに無駄な、あるいは処理するべきではないオブジェクトが大量に書き込まれてしまったとします。そうすると通知メッセージがsubscriptionに滞留しますが、subscriptionを分けていた場合は当該subscriptionのメッセージをpurgeすれば問題は解消します。逆に一つのsubscriptionに集約していた場合、処理するべきメッセージとそうでないメッセージが混在しているので、対応が複雑になってしまいます。

いずれの場合も、利用する環境に応じてデプロイアーキテクチャを検討できるかと考えます。

# まとめ

今回はセキュリティ基盤のログ変換・書込のツールとしてSwarmを紹介しました。このソフトウェアもまだまだ発展途上でありこれが必ずしも正解というわけではないかもしれませんが、基盤構築にあたって何らかの参考になれば幸いです。
