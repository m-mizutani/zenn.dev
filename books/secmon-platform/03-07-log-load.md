---
title: "🛠️ ログ書込の実装要点"
---

今回はデータウェアハウスにおけるETL（Extract, Transform, Load）のうち、ログの書き込み（Load）について紹介します。ログの書き込みは、変換済みのデータをデータウェアハウスに格納するプロセスです。今回はGoogle CloudのBigQueryを利用する想定ですが、BigQueryは外部からのデータ書き込み方法をいくつか提供しています。セキュリティ監視基盤の要件に基づいて、どの方法が最適かを整理します。

# BigQueryへのログ書き込みにおける要件

BigQueryはフルマネージドで非常に便利なデータウェアハウスですが、セキュリティ監視基盤として利用する際にはいくつかの要件があります。

## (要件1) 自動的にスキーマをアップデートできる

セキュリティ監視基盤で利用する多くのログは外部から提供され、スキーマは提供側の都合で変更されることが多いです。また、スキーマ自体も安定せず、同じ提供元からのログでも様々なスキーマが混在することが一般的です。

BigQueryはスキーマレスなデータベースではないため、ログを取り込む際にはスキーマを指定する必要があります。そのため、スキーマが変更されたり、新しいスキーマのログを書き込む場合に自動的にスキーマをアップデートできる仕組みが必要です。

現状のスキーマと合致しないログを投入しようとするとエラーが発生します。手動でスキーマをアップデートする方法もありますが、スキーマの衝突は頻繁に発生するため、運用コストが増加します。さらにエラーが発生するとログ書き込みが停止するため、運用上のリスクもあります。

したがって、ログに対して自動的にスキーマをアップデートする仕組みが必要です。

## (要件2) 遅延をなるべく短くする

セキュリティ監視基盤全体の要件と同様に、ログの書き込みにおいても遅延を最小限に抑える必要があります。遅延を最小化するためにはストリーミング処理が必要ですが、運用コストが課題となるため、一定の遅延は許容せざるを得ません。しかし、遅延が大きすぎると（例えば数時間や数日）、分析や検知が遅れるため、監視基盤全体の要件とバランスを取る必要があります。

# BigQueryへのデータ書き込み方法

BigQueryへのデータ書き込み方法はいくつかあります。外部からBigQueryにデータを書き込む場合、大きく分けて5種類の方法があります。これはBigQueryの一般的な話であるため、すでにご存じの方は読み飛ばしていただいても構いません。

## Streaming Insert (Legacy)

https://cloud.google.com/bigquery/docs/streaming-data-into-bigquery

BigQueryにはストリーミングインサートという機能があります。これは、データを低遅延で書き込むことを目的に提供されている機能です。呼び出し方もシンプルで `insertAll` というAPIを呼び出すだけです。SDKを利用すると以下のように記述できます。

```go
ctx := context.Background()
client, err := bigquery.NewClient(ctx, projectID)
if err != nil {
    return fmt.Errorf("bigquery.NewClient: %w", err)
}
defer client.Close()

inserter := client.Dataset(datasetID).Table(tableID).Inserter()
items := []*Item{
    // Item implements the ValueSaver interface.
    {Name: "Phred Phlyntstone", Age: 32},
    {Name: "Wylma Phlyntstone", Age: 29},
}
if err := inserter.Put(ctx, items); err != nil {
    return err
}
```
https://github.com/GoogleCloudPlatform/golang-samples/blob/HEAD/bigquery/snippets/table/bigquery_table_insert_rows.go より

この方法は長らくBigQueryのデータ書き込み方法として推奨されてきましたが、最近では非推奨とされています。代わりに次に紹介する `Storage Write API` を利用することが推奨されています。

## Storage Write API

https://cloud.google.com/bigquery/docs/write-api

Storage Write APIは、BigQueryにデータを書き込むためのAPIで、Streaming Insertの後継として提供されています。このAPIを利用すると、Streaming Insertよりも高いスループットを実現できるとされています。また、Streaming Insertと異なり、バッチ処理的に書き込むことも可能です。

Storage Write APIはStreaming Insertと比べていくつかの利点がありますが、最もわかりやすいメリットはコストです。Storage Write API の方がデータ量あたりで半額程度のコストでデータを書き込むことができます。

- Streaming Insert: 1 GiBあたり$0.05
- Storage Write API: 1 GiBあたり$0.025

*https://cloud.google.com/bigquery/pricing#data_ingestion_pricing よりUSのコストを参照（2024年12月時点）*

一方、Storage Write APIはStreaming Insertと比べて多機能になったことで、APIの呼び出しは複雑になっています。とても長くなるためGitHubにコード全体をおいています。

https://github.com/m-mizutani/secmon-example-code/blob/main/storage_write_api/main.go

Storage Write APIを利用したログデータの書き込みにおいては、以下のようなポイントがあります。

- 💡**利用するStreamの特性を理解する**: Storage Write APIにはデータ送信の単位として[Stream](https://cloud.google.com/bigquery/docs/write-api#overview)という概念があります。デフォルトで提供されるStreamだけでなく、開発者が必要に応じて遅延の最小化やパフォーマンスの最大化などの観点からStreamを構築することができます。Streamは抽象化されているように見えて、それぞれで全く挙動が違うため、利用する際にはその特性を理解して実装する必要があります。
- 💡**protocol buffer形式への変換が必要**: Storage Write APIはgRPCを用いてデータを送信する都合で、（少なくともGo言語の場合は）開発者側でデータをProtocol Buffer形式に変換する必要があります。筆者の知る限りGoの場合、Go上のデータ形式をそのままProtocol Buffer形式に変換するライブラリは提供されていないため、一度JSON形式に変換してからProtocol Buffer形式に変換する必要があります。ただしこの際、時刻 (`time.Time`) などのデータ型はJSON形式に変換する際に文字列に変換され意図しない挙動になるため、適宜対応する型に変換するという処理を追加する必要があります。
- 💡**スキーマ変更による書き込み失敗の対応**: これまででセキュリティ監視基盤で使うログに対してはスキーマを更新し続ける必要があるという議論をしましたが、BigQueryはスキーマ変更が即座に反映されないという特徴があります。スキーマ変更の命令が完了した後も、[最大で10分程度リトライすることが推奨](https://issuetracker.google.com/issues/64329577?pli=1#comment3)されています。そのため、スキーマ変更の際のリトライ処理を実装するのが望ましいです。

## Batch loading data

https://cloud.google.com/bigquery/docs/batch-loading-data

Cloud StorageからデータをBigQueryにバッチで書き込む方法です。JSON、CSV、Parquet、ORCなどのフォーマットに対応しており、指定したオブジェクトのデータを読み込んでBigQueryに書き込むためのジョブを作成します。

この方法はBigQuery側でジョブを実行してくれるため、開発者側では最低限ジョブの開始だけさせるスクリプトやWorkflowを書くだけで済みます。そのため、ストリーミングインサートやStorage Write APIに比べて開発コストが低いというメリットがあります。しかし一方でセキュリティ監視基盤の要件から考えるといくつか課題があります。

- ⚠️ **完了時間を制御しにくい**: 非同期のバッチ処理のため、データがBigQueryに書き込まれるまでの時間は保証されていません。一般的には数分から数十分で完了するようですが、データ量やジョブの負荷によっては数時間かかることもあります。遅延を最小化したいときに能動的に解決できない可能性があります。
- ⚠️ **実行回数に制限がある**: BigQueryのジョブには[実行回数の制限](https://cloud.google.com/bigquery/quotas#load_jobs)があります。1日あたりテーブルあたり1,500回までとなっているため、Cloud Storageにオブジェクトが作成されるたびに実行すると制限に引っかかる可能性があり、数分おきにまとめて読み込むなどの工夫が必要になります。
- ⚠️ **スキーマ制御が不十分**: Batch loading dataには [Schema auto-detection](https://cloud.google.com/bigquery/docs/schema-detect) という機能があります。これはデータを読み込む際に自動的にスキーマを検出してBigQuery側に反映してくれる機能で一見とても便利に見えるのですが、問題としてオブジェクトの先頭500行しかチェックしてくれないという制限があります。これまでの議論の通り、セキュリティ監視基盤で使うログはスキーマが不安定であり、同じオブジェクト内にも複数のスキーマが混在することが多いです。そのため、この機能では正しく全てのスキーマを検出できない可能性があり、ログの取り込みにおいて最も問題になる点だと考えられます。

このような制約があるため、セキュリティ監視基盤で使うログの書き込みにBatch loading dataを利用を検討する場合は、これらの制約を理解した上で選択することをお勧めします。

## BigQuery Data Transfer Service

https://cloud.google.com/bigquery/docs/dts-introduction

Cloud Storageを含む外部サービスからデータを自動的にBigQueryに取り込んでくれるサービスです。BigQuery Data Transfer Serviceは、BigQueryにデータを取り込むためのジョブを自動的に作成してくれ、さらに新たに追加されたオブジェクトだけを対象としてジョブを作成するなど、自動化された機能が提供されています。挙動としてはBatch loading dataよりもさらに運用は楽でしょう。

しかしCloud StorageからJSONなどの構造化データを取り込む場合、スキーマを制御するための機能は提供されていません。そのため、セキュリティ監視基盤のユースケースでは Batch loading data 以上に扱いが難しいと考えられます。

## Cloud Logging to BigQuery

https://cloud.google.com/logging/docs/export/configure_export_v2

最後の一つの方法として Cloud Logging にデータを流し、それを BigQuery に書き込む方法があります。Cloud Logging は Google Cloud のログ管理サービスで、様々なサービスからのログを集約・管理することができます。Cloud Logging には書き込まれたログを外部にエクスポートする機能があり、そのエクスポート先に BigQuery を指定することができます。

Cloud LoggingからBigQueryにデータを書き込む最大の利点は、スキーマの更新を自動的に行ってくれる点です。BigQueryに書き込むログのスキーマは、Cloud Loggingのログのスキーマに合わせて自動的に更新されます。そのため、セキュリティ監視基盤で使うログのスキーマが不安定である場合でも、スキーマの更新については自動的に行ってくれるため、運用コストを抑えることができます。

一方でCloud Loggingを利用する最大の問題はコストです。[Cloud Loggingは書き込んだデータ量に対して$0.5/GiBのコスト](https://cloud.google.com/stackdriver/pricing)がかかり、これはStorage Web APIを利用する場合のコストの20倍です。そのため、大量のログを取り込む場合はコストがかさむため、運用コストを考慮して選択する必要があります。

# どの書き込み方法を使うべきか

ここまでの議論のとおりBigQueryへの書き込みはいくつかの方法がありますが、まとめると概ね以下のようになります。

| 検討項目 | Streaming Insert | Storage Write API | Batch loading data | Cloud Logging to BigQuery |
| --- |:---:| :---: | :---: | :---: |
| スキーマの自動更新 | ⚠️ | ⚠️ | ❌ | ✅ |
| 遅延の制御 | ✅ | ✅ | ❌ | ✅ |
| 開発コスト | 中 | 高 | 低 | 低 |
| コスト | ⚠️ | ✅ | ✅ | ❌ |

この中でセキュリティ監視基盤で使うログの書き込みというユースケースにおいては、Storage Write APIが比較的有力な選択肢ではと考えます。Storage Write APIはStreaming Insertよりも高いスループットを実現できるとされており、またバッチ処理的に書き込むことも可能になっています。また、Storage Write APIはStreaming Insertと比べてコストが低いため、大量のログを取り込む場合にもコストを抑えることができます。

Storage Write API (またはStreaming Insert) によるログの書き込みにおいては、スキーマを自動更新する機能は直接は備わっていませんが、これらのAPIを利用する際は一度Cloud Storageからデータを読み込む必要があるため、その際にスキーマをチェックして自動更新する処理を追加することができます。また、スケールアウトなどの機能を利用して、遅延をなるべく短くすることができます。

ただし、Storage Write APIは先述した通り比較的複雑ではあるため、開発コストは比較的高いと言えます。しかし裏を返すと高機能ではあるため、ただしく理解して実装すれば効率的かつ柔軟なデータ書き込みを実現できるでしょう。

# まとめ

今回はStorage Write APIを採用し、次回の記事ではStorage Write APIを利用してログの書き込みの実装例について紹介します。しかし、あくまでStorage Write APIが最適であるというわけではなく、それぞれの手法にメリット・デメリットがあります。セキュリティ監視基盤で使うログの書き込み方法を選択する際には、各々の要件に合わせて適切な方法を選択することをおすすめします。
