---
title: "実践セキュリティ監視基盤構築(14): ログ収集と保全の実装例"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の14日目です。

今回は、これまで解説したログ収集フェーズの議論を基に、Pull型によるログ収集・保全の実装例を紹介します。

# ログ収集・保存のフレームワーク化

ログ収集の記事でも紹介した通り、Pull型のログ収集はAPIにアクセスしてデータを収集し、それを保存するという非常にシンプルな処理です。そのため、簡単なスクリプトをいくつか書くだけで済むと考えがちですが、実際にはログ収集の解説で述べたように、注意すべきポイントがいくつかあります。また、ログ収集の処理は外部サービスごとに異なるため、各サービスに対して個別のスクリプトを書くと、サービスの数だけ実行スクリプトが増えてしまいます。これらに異なる実行環境を構築すると、管理が煩雑になります。

そこで今回の例では、ログ収集・保存の処理をフレームワーク化し、管理を統合するアプローチをとりました。ログを収集する部分は外部サービスごとに実装できるようにし、Cloud Storageへの保存を共通化することで全体の実装を簡略化しました。また、実行の制御も同じ方法で行えるようにし、定期的な実行やリトライ処理を統一的に行えるようにしました。

# 定期ログ収集・保存フレームワーク Hatchery

## 実装概要

今回の例では、ログ収集・保存のための `hatchery` というフレームワークを作成しました。`hatchery` はGoのSDKとして実装されており、セキュリティ監視基盤を構築する際にログ収集・保存の処理を簡単に実装できるように設計されています。

https://github.com/secmon-lab/hatchery

`hatchery` は以下のような設計イメージで実装されています。

![](https://storage.googleapis.com/zenn-user-upload/a949735ca1fe-20241124.jpg)

`hatchery` では "Stream" と呼ばれるデータ収集と保存のパイプラインを管理します。Streamはsourceとdestinationで構成されます。sourceはログデータの提供元（例: Slack、1Password、Falcon Data Replicator）で、destinationはデータ保存先（例: Google Cloud Storage、Amazon S3）です。複数のStreamを定義し、並行して実行することができます。

先述した通り、`hatchery` はツールではなくフレームワークです。この手の処理をするソフトウェアは外部から設定ファイルを読み込んで実行することが一般的ですが、`hatchery` はGoのSDKとして実装されています。具体的には以下のようにStreamを定義します。

```go
streams := []*hatchery.Stream{
    hatchery.NewStream(
        // source: Slack Audit API
        slack.New(secret.NewString(os.Getenv("SLACK_TOKEN"))),
        // destination: Google Cloud Storage
        gcs.New("mizutani-test"),

        // タグとして "hourly" を指定
        hatchery.WithTags("hourly"),
    ),
}
```

この例では、SlackのAudit APIからデータを取得し、Google Cloud Storageに保存するStreamを定義しています。`hatchery` はこのStreamを実行することで、SlackのAuditログを定期的に保存する処理を実現します。実行のためのコードは以下のようになります。

```go
if err := hatchery.New(streams).CLI(os.Args); err != nil {
    panic(err)
}
```

ここでは、コマンドライン引数を受け取り、指定されたStreamを実行するCLIツールを作成しています。`CLI` を指定することで、コマンドラインオプションなどを自動的に処理して指定されたStreamを実行します。以下のようにコマンドラインから実行することができます。

```bash
$ go build -o my_hatchery main.go
# -tオプションにより、タグ "hourly" のStreamを実行
$ ./my_hatchery -t hourly
```

Streamを増やしタグでまとめて指定することで、複数のサービスからのログ収集を同時に実施することができます。タグは主にログ収集の単位を指定するために使用します。例えば、毎分ごとに実行するStream、10分に一度実行するStream、1時間に一度実行するStreamがそれぞれあった場合、外部のスケジューラーを起動に用い、実行時にそれぞれのタグを指定します。これによって、複数の実行間隔を持つStreamをまとめて管理することができます。

# 実装のポイント

先述した通り、`hatchery` はいわゆるツールではなくGo言語のフレームワークとして実装されています。そのように実装した理由を含めて、実装のポイントを以下にまとめます。

## 拡張性

まず大きな理由は拡張性です。ログ収集の処理は外部サービスごとに異なるため、それぞれのサービスに対して個別の実装を行う必要があります。`hatchery` では、外部サービスごとに `source` インターフェースを定義し、それを実装することで新たなサービスに対応できるようにしています。また、同様に `destination` インターフェースも定義しており、新たな保存先に対応できるようにしています。

Go言語でもロジックを外部から取り入れるために[プラグインの機構](https://pkg.go.dev/plugin)が用意されています。しかし実際にこれを使いこなそうとするとツール側とのバージョン管理や依存関係の管理が難しくなります。また、シグネチャのズレなどにも注意が必要となります。過去の実装で試したことがありましたが、運用が難しく利用を断念しました。他にも[WebAssemblyを利用したプラグインの仕組み](https://knqyf263.hatenablog.com/entry/2022/08/30/052303)などもあるのですが、これはtinygoを前提としており、ログの処理において機能が十分ではない可能性を考慮して採用を見送りました。

結果として、

- ロジックを自由に実装できる
- バージョン管理や依存関係の管理が容易[^go-mod]
- 外部で作成された拡張も取り込むことができる

などを実現するためには、Go言語のSDKとして実装することが最適であると判断しました。例えばHTTPリクエストを送信してログを取得するsourceは以下のように実装できます。

[^go-mod]: ただし外部で作成された拡張を取り込む場合は、その拡張が利用しているhatcheryのバージョンと合わせる必要があり、ここはまだ改良の余地があると考えています。

```go
getAuditLogs := func(ctx context.Context, p *hatchery.Pipe) error {
    resp, err := http.Get("https://example.com/api/audit")
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if err := p.Spout(ctx, resp.Body, metadata.New()); err != nil {
        return err
    }

    return nil
}
```

実際にはページネーションの処理などが必要になる場合もありますが、このようにHTTPリクエストを送信してログを取得する処理を実装することができます。

## ログ保存処理の抽象化

この実装のポイントの一つはログの保存処理を共通化している点です。ログ収集が外部サービスごとに異なるのに対し、ログの保存処理は共通化できるため、保存処理を共通化することで全体の実装を簡略化できます。

保存処理は以下の2つのポイントによって抽象化しています。

- **データの受け渡しは `io.ReadCloser` に統一する**: データはあくまで加工せずそのまま保存する、という原則から、データの受け渡しは `io.ReadCloser` に統一しています。これにより、データの加工処理を行うことなく取得したデータをそのまま保存することで、保存処理を共通化できます。
- **メタデータを渡して保存先のオブジェクト名決定などに利用する**: ログの保全で解説した通り、ログの保存先のオブジェクト名はいくつかの要素によって決定されます。

現在はログをCloud Storageのみに保存していますが、この抽象化によってAmazon S3など他のオブジェクトストレージだけでなく、Kinesis Data StreamやPub/Subに直接データを送出するということも将来的には考えられます。

## 設定値の管理

`hatchery` では設定値をハードコードもできるし、環境変数から取得することも想定しています。組織専用のバイナリを作成するため、値をそのまま埋め込んでおくこともできます。一方でクレデンシャルなどの秘匿値は環境変数から取得することで、安全に運用することができます。

環境（開発環境、QA環境、ステージング環境、本番環境など）ごとに設定値を変更する場合は、全ての設定値を環境変数経由で値を与えることもできますし、環境を示す値（例 `dev`, `qa`, `stg`, `prd`）だけ渡して、その値に応じて設定値を切り替えるというようなことも可能です。どちらの方が見通しがいいか、管理しやすいかは組織のポリシーなどにも依存するため、適宜選択できるようにしています。

```go
configs := map[string]map[string]string{
    "dev": {
        "targetURL": "https://dev.example.com/api/audit",
    },
    "prd": {
        "targetURL": "https://prd.example.com/api/audit",
    },
}

config, _ := configs[os.Getenv("ENV")]
```

設定値の管理においていわゆる設定ファイル（YAMLやJSON）を使うことも考えましたが、以下のような理由で棄却しました。

- **バリデーションや構造体の管理が煩雑になる**: 設定ファイルを読み込む際に構造や値のバリデーションの管理が必要になります。YAMLやJSONからパースする場合、ツールを起動しないとバリデーションを実行できないので、記述する際の体験があまりよくありません。[cue](https://cuelang.org/) だと記述中のバリデーションは実施できますが、cue側とGo側で構造体を二重管理しなければならないという課題があります。
- **環境変数から値を取得したい**: 部分的にはハードコードで問題ない設定値ですが、やはりクレデンシャルなどは環境変数から取得したいという要求があります。JSONやYAMLだと環境変数から取得するために特殊な処理が必要となってしまいます。
- **ツールの依存関係を増やしたくない**: [pkl](https://github.com/apple/pkl) はバリデーションもできつつ、Goの構造体を生成してくれるツールなのですが、実行にjavaが必要となるため、ツールの依存関係が増えることを嫌いました。

これらの理由により、今回は設定値を直接Goのコードとして表現するという方法を採用してみました。

# デプロイ構成

構成についてはアーキテクチャで説明した通り、Cloud SchedulerとWorkflowsを利用して定期的にCloud Run上で起動させます。図としては以下のとおりです。

![](https://storage.googleapis.com/zenn-user-upload/7fa1f0dcbd2d-20241127.jpg)

WorkflowsからCloud Runを起動する際、引数を書き換えることによって、実行するStreamを指定することができます。複数タグを用意しておくことで、実行間隔を複数用意することができます。以下のYAMLは毎分実行するための `minutely` タグを指定してCloud Runを起動する例です。

```yaml
main:
  params: [event]
  steps:
    - run_job:
        call: googleapis.run.v1.namespaces.jobs.run
        args:
          name: namespaces/my-project/jobs/hatchery
          location: asia-northeast1
          body:
            overrides:
              containerOverrides:
                args:
                  - "-t"
                  - "minutely"
        result: job_execution
    - finish:
        return: ${job_execution}
```

# まとめ

今回は、ログ収集・保存の処理をフレームワーク化することで、管理を統合するというアプローチをとりました。`hatchery` はGoのSDKとして実装されており、セキュリティ監視基盤を構築する際にログ収集・保存の処理を簡単に実装できるように設計されています。これはあくまで実装の一例ですが、参考になれば幸いです。