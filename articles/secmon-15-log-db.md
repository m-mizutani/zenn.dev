---
title: "実践セキュリティ監視基盤構築(15): ログデータベースの設計"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の15日目です。

ここまでのログ収集・保全の記事ではログデータをCloud Storageに保存するところまでの流れを解説しました。続けてログデータの変換・投入について解説したいのですが、その前に投入先のデータベースの設計について考えてみます。

基本的にはビジネス系の大規模データを扱う際のスキーマ設計と同じですが、いくつかセキュリティ監視の特性にあわせた設計もあるので、それについても触れていきます。

# データウェアハウスの選択

これまででも解説してきた通り、本アドベントカレンダーではBigQueryをデータウェアハウスとして利用します。BigQueryはストレージコストが安くフルマネージドであるため、大量のデータを抱え込みかつ運用コストをなるべく抑えたいセキュリティ監視基盤の構築に適しています。

他の選択肢としては以下のようなものがあり、参考までに挙げておきます。

- **Amazon Redshift**: AWSのデータウェアハウスサービスです。クラスタを構築するためのリソース選択やスケールを調整できるため、柔軟な運用が可能です。ただしコストが定常的にかかるため、データ量やクラスタサイズが大きくなるとコストに影響しやすいです。
- **Amazon Athena**: AWSのサーバレスなクエリサービスです。S3に保存されたデータをクエリできるため、データウェアハウスとして利用できます。ただしS3に保存するデータの管理などは自分でやる必要があるため、運用コストは高くなりやすいです。
- **Snowflake**: クラウドネイティブなデータウェアハウスサービスです。クラウドプラットフォームに依存しない設計となっており、複数のクラウドプラットフォームに対応させやすいですが、一方でIAM管理がクラウドプラットフォームから独立するため権限の管理に注意する必要があります。
- **Elasticsearch**: ログデータの検索に特化したデータベースです。ログデータの高速な検索や可視化は強力ですが、インスタンスを常に起動し続ける必要があり、かつストレージのコストもほかと比べ高額になりやすいです。データウェアハウス本体ではなく補助的なデータベースとして利用するアプローチがあります。

# ログデータベースのスキーマ設計

これまでも述べてきましたが、セキュリティ監視に利用するログデータの特徴として、ログの大部分が外部から提供されスキーマも提供元の特性に合わせて決定される、という特徴があります。BigQueryはスキーマレスなデータベースではないため、スキーマについての設計が必要になります。スキーマについてはスキーマの正規化、およびスキーマの管理の2つの観点から検討する必要があります。

## (ポイント1) スキーマの正規化

セキュリティ監視に関連したイベントを取り扱う場合、ログデータは概ね共通したフィールドを持つように思えます。例えば、イベントの種別、発生時刻、発生元のIPアドレス、発生元のユーザ名、などです。しかし、実際にはログデータの種類によってフィールドが異なることが多いため、すべてのログデータを正規化するのはかなり困難です。具体的な例をいくつか挙げます。

- **送信元IPアドレス**: 例えば近年のユーザー向けネットワーク環境はIPv4ではほとんどがNAT（Network Address Translation）によってインターネットと通信しています。EDRのログで端末側のIPアドレスと言った場合、端末に直接付与されたIPアドレスとNATを通過した後のIPアドレスの両方が「送信元IPアドレス」の意味を持ち、そのどちらを使うべきかは文脈によって異なります。またIPv6の場合、複数のIPアドレスが端末に付与されることもあり、1つのフィールドに収めるのは難しいです。
- **イベントの主体（SubjectやPrincipal）**: イベントを表す際に、そのイベントを実行した主体を表すフィールドがあります。これも1つのフィールドとして括られる場合がありますが、実際にはOSのユーザ名とユーザ番号など複数の表記方法があったり、ユーザ名とグループ名が混在していたりします。さらに Impersonation などの概念がある場合、イベントの主体が複数存在することもあり、これも必要な情報は文脈によって異なります。

このように、同じような属性値であってもログの提供元によって文脈などが異なるため、すべてのログデータを正規化するのは困難です。なんとか全てのログを正規化しようと試みたSIEM製品も見たことがありますが、結局数百のフィールドを持つことになり、あまり正規化の効果があるとは言えないと考えられました。

このことから少なくとも完全な正規化は諦め、ごく少数の特定のフィールドだけは正規化する、というアプローチが有効です。詳しくは後述します。

## (ポイント2) スキーマの管理

ログの正規化ができない場合であっても、スキーマ自体は管理する必要があります。BigQueryはスキーマを持つデータベースということもあり、任意のスキーマのログを取り扱う場合にはそのスキーマを把握してログを取り込むことが重要です。これは以下の3つの理由からです。

- **クエリするためのスキーマ把握**: BigQueryは効率的に検索するためには目的のフィールドのみにアクセスするようにクエリを最適化します。そのため、クエリを書く際にはどのフィールドにどのようなデータが入っているかを事前に把握しなければなりません。各フィールドの説明が整理されている状態が理想ですが、フィールド名と階層構造だけでも概ね意味を推定できるので、それが事前にあるかで大きく違います。
- **フィールドの衝突回避**: BigQueryはJSONデータとしてフィールドに任意のスキーマのデータを文字列形式で格納し、検索時にパースして利用できます。これはスキーマ管理をしなくてもデータを格納できるため便利ですが、逆に言うとスキーマが保証されず、同じフィールド名で別の型が混在するという状況も容易に起こり得ます。これを避けるためにもスキーマの管理が重要です。
- **スキーマの変更**: 取得する外部のサービスのログはスキーマが変更されることがあります。これはフィールドの追加だけでなく、破壊的変更が発生する場合もあります。これを把握せずにログを取り込むと、様々なスキーマが混在してしまい、クエリの作成やデータの分析が困難になります。

上記の通りスキーマ管理は必要なのですが、人間が手作業でスキーマを管理するのは非常に困難です。そのため、スキーマの管理には自動化が必要です。具体的な方法については、ログの変換・書込の記事で解説します。

## スキーマの設計例

2つのポイントを踏まえたうえで、スキーマの設計例を示します。以下はセキュリティ監視のためのログデータベースのスキーマの例として以下のようなフィールドを持つ構造を考えます。

- `id`: ログのユニークなIDです。複数回書込が発生した場合に備えて、重複排除に利用します。取得元のログにIDがある場合はそのまま利用します。
- `timestamp`: ログの発生時刻です。パーティショニングに利用します。取得元のログにタイムスタンプがある場合はそのまま利用します。
- `ingested_at`: ログが取り込まれた時刻です。これは元のログの値に依存せず、現在時刻を記録します。
- `data`: ログの本体です。取得元のログの内容をそのまま格納します。このフィールドはRECORD型として、取得元のログのスキーマをそのまま格納します。

このスキーマは全体的な正規化は諦め、`data`フィールドに取得元のログの内容をそのまま格納するアプローチを取っています。この `data` 以下のスキーマを常にアップデートし続けることで、取得元のログの変更に対応できるようになります。

他の3つのフィールドはログ検索の基本となる範囲指定と重複排除に利用します。 `timestamp` はそのまま検索対象となる時間指定に、 `id` および `ingested_at` は重複排除に利用します。同じ `id` のログは同一ですが、例えば後から取り込まれたログは変換処理が修正されている場合があるので、 `id` が同じでも `ingested_at` が新しいログを優先して利用することで、最新のログを取得できます。

これは例えば以下のようなクエリで統一して重複排除と時刻指定をすることができます。

```sql
WITH
  latest AS (
  SELECT
    id,
    MAX(ingested_at) AS ingested_at
  FROM
    `my_project.my_dataset.event_logs_v1`
  WHERE
    TIMESTAMP_TRUNC(timestamp, DAY) = TIMESTAMP("2024-11-30")
  GROUP BY
    id )
SELECT
  logs.*
FROM
  `my_project.my_dataset.event_logs_v1` AS logs
INNER JOIN
  latest
ON
  logs.id = latest.id
  AND logs.ingested_at = latest.ingested_at
WHERE
  TIMESTAMP_TRUNC(timestamp, DAY) = TIMESTAMP("2024-11-30")
LIMIT
  100
```


# プロジェクトの設計

セキュリティ監視基盤のために利用するBigQueryのためのプロジェクトの構成は様々ですが、一つのアプローチとして以下のような構成が考えられます。

## プロジェクトの構成例

- `source` プロジェクト: セキュリティ監視基盤のパイプラインによって取得したデータを投入するためのプロジェクト
- `dwh` プロジェクト: データマートを実装するためのプロジェクト

この構成はセキュリティ監視のために基盤上のパイプラインで取得したもの以外にも、利用できるログデータがある場合に効果的です。具体的には以下のようになります。

![](https://storage.googleapis.com/zenn-user-upload/5c37bdaf17e1-20241129.jpg)

セキュリティ監視でのみ利用するログは`source` Projectに投入しますが、他の目的で収集したログを利用したい場合も考えられます。その場合、データの保持をするプロジェクトとクエリをするプロジェクトを分けることで、以下のようなメリットがあります。

- **セキュリティ監視に利用したいデータセットの参照を一つのプロジェクトに集約できる**: 一つのプロジェクトに集約することで一覧性がよくなり、クエリの構築をする際にも便利になります。
- **予算管理をしやすい**: このDWHプロジェクトはセキュリティ監視の目的にのみ利用することで、複数のデータソースを参照する場合もセキュリティ監視にかかるコストを把握しやすくなります。
- **データとモデルを分離できる**: データの保持とモデルの構築を分離することで、データの保持をするプロジェクトはデータの保持に特化した設計にできます。また、モデルに問題があった場合も修正が容易になります。正規化をしたい場合に便利なアプローチとなります。

`dwh` プロジェクトに集約させるためにはいくつかの方法がありますが、一つは [dbt](https://www.getdbt.com/) のようなツールを利用する方法です。dbtはデータウェアハウスのためのモデルを管理するためのツールで、SQLを使ってデータの変換や集計を行うことができます。

## 注意点

このような構成は便利な反面、以下のような注意点があります。

- **データセットの地域を統一する**: BigQueryのデータセットは地域を統一する必要があります。`source` プロジェクトと `dwh` プロジェクトで地域が異なるとクエリやデータの結合ができなくなるため、地域を統一する必要があります。
- **コピーかビューか**: `source` プロジェクトのデータを `dwh` プロジェクトにコピーするか、ビューを作成するかは検討が必要です。ビューを作成する場合は手軽である反面、権限管理が `source` 側に依存するという点に注意が必要です。コピーの場合は権限は `dwh` プロジェクトで管理できますが、データのコピーが発生するためコストがかかります。

# データセット、テーブルの設計



- テーブルの分割
    - スキーマの分割
- データセットの分割
    - セキュリティ監視以外の活用も考えられる場合、権限設定をしやすいように区切る
        - ログの発生元事に切るのがベター
    - ただし必ず同じregionに置くように留意する

# コスト圧縮のための設計

- Physical storage v.s. Logical storage
- partition分割
    - ただし切リ方を間違えると逆にコストがかかる

# まとめ