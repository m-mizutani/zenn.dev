---
title: "🛠️ アラート検知の実装例"
---

前回はアラート検知の処理系について解説しましたが、今回はその実装例を紹介します。

# バッチ型アラート検知の要件

まず、セキュリティ監視基盤におけるアラート検知の要件を簡単におさらいします。今回は、データウェアハウスであるBigQueryに定期的にクエリを発行してアラートを検知するバッチ型のアラート検知を前提とします。

- ✔ **テスト可能性**: アラート検知のルールはロジックそのものであり、期待通りに動作するか、既存のルールに影響を与えないかをテストできることが重要です。
- ✔ **テスト自動化**: テストを自動化することで、ルールの正しさを継続的に確認できるようにします。
- ✔ **ルールの記述性**: ルールが増えても読みやすく、変更しやすいように、構造化しやすい形式であることが望ましいです。
- ✔ **コスト最適化**: データウェアハウスにクエリを発行するたびに課金が発生するため、コストを最適化する仕組みが必要です。

# アラート検知ツール OverSeer

今回実装したのは、バッチ型アラート検知のためのツールである `overseer` です。`overseer` はBigQueryに対してクエリを発行し、その結果に基づいてアラートを検知するツールです。検知したアラートはPub/Subに通知され、後段のアラート対応システムと連携できます。

https://github.com/secmon-lab/overseer

![](https://storage.googleapis.com/zenn-user-upload/f1ac51ba6006-20241214.png)

Overseerの最大の特徴は、BigQueryから**ログデータを抽出するためのSQLクエリ**と、その結果から**アラートを検知するためのRegoポリシー**を組み合わせてアラート検知ルールを記述できる点です。具体的な動作としては、SQLクエリで抽出したログデータをCloud Storageに一時的に保存し、それをRegoポリシーで読み込んで評価します。このアーキテクチャを採用することで、各要件を満たすことができます。

## ✅️ Regoのルールの記述性の高さを利用

BigQueryからデータを抽出するためのSQLは表現力の高いDSLですが、ルールの構造化という観点ではやや不向きです。

例えば、ユーザごとに許可されたアクションのログを抽出するSQLクエリを考えます。SQLの場合、以下のように記述します。

```sql
SELECT logs.user, logs.action
FROM logs
JOIN (
  SELECT 'user1' AS user, 'create' AS action UNION ALL
  SELECT 'user1', 'view' UNION ALL
  SELECT 'user2', 'view'
) AS allowed_list
ON logs.user = allowed_list.user AND logs.action = allowed_list.action;
```

ルールに利用するユーザとアクションの組み合わせが増えると、SQLクエリの記述が複雑になります。`allowed_list` をBigQuery上のテーブルや外部のCloud Storageに持つ方法もありますが、ルールに関する内容は一括で管理するほうが見通しが良く、バージョン管理の観点でも有利です。また、より複雑な構造になった場合、直感的でないデータ構造になることも考えられます。

一方、Regoの場合は以下のように記述できます。

```rego
allowed_list = {
  "user1": ["create", "view"],
  "user2": ["view"],
}

match {
  input.action == allowed_list[input.user].action
}
```

一般的なマップ型や配列型を使った記述ができるため、構造化ルールを記述しやすくなっています。また、評価の単位であるルールを分割しやすく、複雑なルールを記述する場合でもシンプルに記述できます。Regoの方がより直感的に構造化しやすいと考えています。

ただし、BigQueryからのデータ抽出はSQLで行う必要があるため、SQLとRegoの組み合わせという形になります。ルールの棲み分けの考え方は以下のとおりです。

- **SQL: 検査すべきログの抽出と集約** 検査すべき対象のログデータを抽出し、必要に応じて集計、集約します。イメージとしては「監査やセキュリティチェックなどで人間が確認するような一覧を作成する」という役割を持ちます。
- **Rego: 抽出・集約されたログの評価** SQLで抽出したログデータをRegoで評価し、セキュリティ上の問題であると考えられるものをアラートとして検知します。イメージとしては「作成された一覧をもとに、リスクがあるかの判断をする」という役割を持ちます。

このように、SQLとRegoの役割を分けることで、それぞれの得意分野を活かすことができます。具体的な実装例については[利用例](#Overseerの利用例)で紹介します。

## ✅️ OPA・Regoの機能を使ったテスト可能性・テスト自動化

BigQueryのクエリを実行してアラートを検知する処理であってもテストは可能です。例えば、BigQueryの[Emulator](https://github.com/goccy/bigquery-emulator)を利用したり、都度BigQuery上にデータセットを構築してクエリしてテストする[フレームワーク](https://github.com/tosun-si/bigtesty)を利用することができます。

Regoも同様にテストすることができます。RegoのエンジンであるOPAにはもともとテストの機能が備わっているため、それを利用することでRegoのテストを自動化できます。具体的なテストの方法については[公式ドキュメント](https://www.openpolicyagent.org/docs/latest/policy-testing/)を参照してください。

今回の仕組みでは、BigQueryから取得したログデータをテスト用に転用することで、Regoのテストを簡単に構築できます。構築したテストはOPAコマンドで実行できるため、CI/CDパイプラインに組み込むことで継続的にテストを実行できます。

## ✅️ データ抽出とルール評価の分離によるコスト最適化

BigQueryにクエリを発行するたび、スキャンするデータ量に応じて課金が発生するため、コストを最適化する仕組みが必要です。特に大量のデータがあるテーブルに対してクエリを発行する場合、全データをスキャンするとコストが高くなります。もちろんPartitioningやClusteringを利用することでコストを抑えることができますが、それでもスキャン対象が数百GBを超える場合、繰り返しクエリを発行するとそれなりの課金になります。

この問題に対しては、クエリの結果を一時的にCloud Storageに保存し、そのデータをRegoで評価するという方法を採用しています。一つのクエリでなるべく多くのアラートを対象としたデータを取れるようにし、そのデータをCloud Storageに保存しておくことで、Regoでの評価を高速に行うことができます。また、Cloud Storageに保存したデータは後段の処理にも利用できるため、一度取得したデータを再利用することでコストを抑えることができます。

また、ルール調整やデバッグの観点でも、Cloud Storageに保存したデータを利用することで、クエリの結果を再利用することができます。ルール調整やデバッグは評価の実行と結果を基にした修正を繰り返すため、そのたびにクエリを発行するとコストがかかります。Cloud Storageに保存したデータを利用することで、そのコストを抑えることができるというメリットがあります。

# Overseerの利用例

具体的にどのようにOverseerが動作するのかを紹介します。今回はGoogle Cloudの監査ログを対象として不審なリソースの操作がないかを検知する例を紹介します。

## ルールの記述

まずはルールを記述します。先述した通り、ログデータを抽出するSQLとルールを評価するRegoをそれぞれ記述します。Google Cloudの監査ログの詳細については以下を参照してください。

https://cloud.google.com/logging/docs/audit

Google Cloudの監査ログはCloud Loggingに出力され、sink設定をすることでBigQueryへデータ転送することができます。今回はBigQueryに転送された監査ログを対象として、不審なリソースの操作を検知するルールを記述します。

https://cloud.google.com/logging/docs/export/configure_export_v2

以下がSQLの例です。

```sql:query/google_audit_activity.sql
SELECT
    -- ルールの評価に使いたい項目を取得

    -- Group By によって集約する項目を指定
    protopayload_auditlog.authenticationinfo.principalemail AS principal,
    activity.resource.labels.project_id,
    protopayload_auditlog.methodname AS method_name,
    authz.resource,

    -- 集約関数を使って集約する。リスト型にすることで複数の値を保持できる
    ARRAY_AGG(DISTINCT protopayload_auditlog.resourcename) AS resource_names,
    ARRAY_AGG(DISTINCT protopayload_auditlog.requestmetadata.callerip IGNORE NULLS) AS ip_addrs,
    ARRAY_AGG(DISTINCT protopayload_auditlog.responsejson IGNORE NULLS) AS responsejson,

    -- 最新のログのタイムスタンプを取得
    MAX(timestamp) AS latest,
    -- 全体で何件発生したのかを取得
    COUNT(*) AS count,
FROM
    `your-project.your-google-audit-logs.activity` AS activity,
    UNNEST(protopayload_auditlog.authorizationinfo) AS authz -- 認可情報がリストなので展開
WHERE
    -- 1日前の24時間文のログを取得
    TIMESTAMP_TRUNC(timestamp, DAY) = TIMESTAMP_TRUNC(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY), DAY)

    -- ルールの評価に使いたいログの条件を指定
    AND protopayload_auditlog.methodname LIKE ANY(
        -- Impersonation など権限昇格系の操作
        "iam.serviceAccounts.actAs",

        -- サービスアカウントの作成・削除
        "google.iam.admin.v1.CreateServiceAccount",
        "google.iam.admin.v1.CreateServiceAccountKey",
        "google.iam.admin.v1.DeleteServiceAccount",

        -- インスタンスの作成・削除
        "v1.compute.instances.insert",
        "v1.compute.instances.delete",
        "v1.compute.instances.bulkInsert",
        "v1.compute.instantSnapshots.insert",
        "v1.compute.instantSnapshots.delete",

        -- IAMポリシーの変更
        "%.SetIamPolicy"
    )
    AND activity.resource.labels.project_id LIKE ANY(
        -- 特定のプロジェクトに対してのみ検知する
        "%-prd",
        "%-stg"
    )
GROUP BY
    protopayload_auditlog.authenticationinfo.principalemail,
    protopayload_auditlog.methodname,
    activity.resource.labels.project_id,
    authz.resource
LIMIT
    10000 -- 念の為上限を設定（これはコスト抑制には関係ないので注意）
```

基本的な処理としては

- 1日前の24時間分のログに対して
- 特定のプロジェクトとAPI呼び出しのログに絞り
- Principal、API名、プロジェクト、リソースによってグループ化し集計

というのが大まかな処理です。このクエリを実行することで、1日前の24時間分のログに対して特定のプロジェクトに対して行われた特定のAPI呼び出しのログを取得することができます。これによって「誰が」「どのリソースに対して」「どのような操作をしたのか」という情報を集約して取得することができます。

次にRegoのルールを記述します。

```rego:policy/google_audit_activity.rego
# METADATA
# name: Check Google Activity logs
# description: test rule
# custom:
#   input:
#     - google_audit_activity
#   tags:
#     - daily

package google_activity

import rego.v1

alert contains {
	# これがアラートとして発出されるデータ構造になる
	"title": sprintf("Unexpected instance manipulation (%s)", [r.principal]),
	"timestamp": r.latest,
	# 任意のパラメータをアラートに追加できる
	"attrs": {
		"principal": r.principal,
		"method_name": r.method_name,
		"resource_names": r.resource_names,
	},
} if { # ここにルールを記述
	# SQLによって抽出されたデータは google_audit_activity に配列で格納される
	# 今回のルールでは1件ずつ評価するため、配列の要素を _ で取り出す
	r := input.google_audit_activity[_]

	# メソッド名がインスタンスの作成・削除に該当する場合のログだけ見る
	r.method_name == [
		"v1.compute.instances.insert",
		"v1.compute.instances.delete",
	][_]

	# Google Cloud標準で用意されているサービスアカウントを除外
	allowed_account_suffix := [
		"@container-engine-robot.iam.gserviceaccount.com",
		"@cloudservices.gserviceaccount.com",
	]

 	# 末尾がすべて allowed_account_suffix にマッチしないことを確認
	every i in allowed_account_suffix {
		not endswith(r.principal, i)
	}
}
```

このルールはインスタンスの不審な操作を検出するための条件と発出するアラートの情報を定義したルールです。このルールはSQLで実行したログデータを評価し、特定のサービスアカウント以外がインスタンスの作成・削除を行った場合にアラートを発出します。

いくつかのポイントを説明します。まず先頭には `METADATA` というコメントがあります。これはルールのメタデータを表記するためのコメントで、[Regoの仕様](https://www.openpolicyagent.org/docs/latest/policy-language/#metadata)で定義されています。 `name`、`description` は共通のアノテーションとして機能しますが、 `custom` フィールドには自由なデータ形式を記述できます。Overseerではここに `input` と `tags` を指定することで、評価ルールのコントロールをしています。

```rego
# METADATA
# name: Check Google Activity logs
# description: test rule
# custom:
#   input:
#     - google_audit_activity
#   tags:
#     - daily
```

`input` はSQLで抽出したログデータを指定します。このルールは `google_audit_activity` というSQLで抽出したログデータを受け取ることを想定しています。`tags` はこのルールを評価するタイミングを指定するためのタグです。このルールは `daily` というタグを指定しており、Overseer起動時に `daily` タグを指定することでこのルールを評価することができます。 `daily` タグを指定した起動を1日一度にすることで、実行頻度が制御できるようになります。

SQLによる1回のデータ取得に対してRegoは様々なルールを記述することができ、クエリに対するコストを圧縮することができます。今回のGoogle Cloudの監査ログの取得対象APIを増やすことで、例えば以下のようなルールをまとめて評価できるようになります。

- 特定のPrincipal以外によるサービスアカウントの作成・削除
- 不必要なサービスアカウントキーが発行される
- クラウド上のプロダクトのみで利用されるシークレットが外部ネットワークから参照される
- クラウド上のプロダクトのみが接続するデータベースに外部ネットワークから接続される
- 特定のサービスアカウントに強力な権限が付与される
- 特定のプロジェクトに対して利用を想定していないAPIが呼び出される

## 検知の実行

次に実際に検知を実行します。OverseerはCLIツールとして提供されており、以下のように実行することができます。

```bash
% export OVERSEER_BIGQUERY_PROJECT_ID=your-bq-project
% export OVERSEER_GCS_BUCKET=your-gcs-bucket
% export OVERSEER_NOTIFY_PUBSUB_PROJECT=your-pubsub-project
% export OVERSEER_NOTIFY_PUBSUB_TOPIC=your-pubsub-topic
% overseer run -t daily -r ./policy -q ./query
```

`OVERSEER_BIGQUERY_PROJECT_ID` はBigQueryのジョブを実行するためのプロジェクトID、`OVERSEER_GCS_BUCKET` は一時的なデータを保存するためのCloud Storageのバケット名、`OVERSEER_NOTIFY_PUBSUB_PROJECT` と `OVERSEER_NOTIFY_PUBSUB_TOPIC` はアラートを通知するためのPub/SubのプロジェクトIDとトピック名を指定します。`overseer run` コマンドに `-t` オプションでタグを指定することで、指定したタグのルールを評価することができます。`-r` オプションでルールのディレクトリ、`-q` オプションでクエリのディレクトリを指定します。

これを実行すると、まず対象となるRegoポリシーのメタデータが読まれ、 `input` で指定されたログデータがBigQueryから取得されます。今回の例ではクエリが1つしかありませんが、複数あった場合はタグで指定されたポリシーの `input` を集約し、必要なクエリだけを実行します。実行されたログデータはCloud Storageに保存され、Regoポリシーが評価されます。評価された結果にアラートが含まれていた場合、指定したPub/Subトピックにアラートのデータが通知されます。

## ルールの調整

先述した通り、アラート検知のルールを作成、修正する場合はトライアンドエラーが必要になりますが、クエリを連発するとコストが掛かったり、ログデータの取得に時間がかかるといった問題があります。Overseerにおいてもデータの抽出・集計の部分についてはBigQueryへ実際にクエリをすることになりますが、抽出・集計されたログデータはCloud Storageに保存されるため、そのデータを再利用することでコストを抑えることができます。データの保存場所も `OVERSEER_GCS_BUCKET` の代わりに `OVERSEER_FS_DIR` を指定することでローカルディスクに保存することもできます。

```bash
% overseer fetch -t daily -r ./policy -q ./query
```

まず `fetch` コマンドを実行することで、クエリ結果を取得します。この際、 `job_id` というパラメータが返却されます。この `job_id` を指定することで、前回のクエリ結果を再利用することができます。

```bash
% overseer eval -t daily -r ./policy -q ./query -j job202411071539_0193055981f173208xxxxxxxxxx
```

結果の出力も、 `--notify-out stdout` というオプションを指定することで標準出力に出力することができます。このようにすることで、ルールの調整やデバッグを行う際に、クエリを繰り返し実行することなく、前回のクエリ結果を再利用することができます。

# Overseerのデプロイ構成

最後にOverseerのデプロイ構成について説明します。OverseerはCLIツールとして提供しており、Dockerfileによってコンテナ化して実運用環境で使うことを想定しています。 `./query` と `./policy` にはそれぞれクエリとポリシーのファイルを配置しておくことで、コンテナ起動時にそれらを読み込むことができます。

```Dockerfile
FROM ghcr.io/secmon-lab/overseer:v0.0.x

COPY policy /policy
COPY query /query

WORKDIR /

# base image of overseer is gcr.io/distroless/base:nonroot
USER nonroot

ENV OVERSEER_QUERY=/query
ENV OVERSEER_POLICY=/policy

ENTRYPOINT ["/overseer", "run"]
```

このようにしてコンテナをビルドし、イメージをArtifact Registryにアップロードした後、Cloud Runにデプロイします。具体的には以下のような構成になります。

![](https://storage.googleapis.com/zenn-user-upload/27bc291f8d4e-20241214.jpg)

Cloud RunはCloud SchedulerとWorkflowsによって定期的に起動します。他の構成と同様ですが、Workflowsをわざわざ間に挟んでいるのは起動オプションを変更するためです。 `-t` オプションでタグを指定することで、評価するルールを変更することができます。そのためタグに実行間隔を示す `daily` などを指定することで、そのタグのルールを1日一度に評価するように設定しています。これをWorkflows側で変更して起動することで、クエリとルールの実行間隔を制御できるようになります。

# まとめ

今回はバッチ型のアラート検知の実装例について紹介しました。バッチ型でも実装方法はこれに限らず様々な方法が考えられますし、ストリーム型のアラート検知と組み合わせることでより効果的な監視基盤を構築することができます。Overseerはあくまで実装例ですが、ルールの構成やアーキテクチャなどが参考になれば幸いです。
