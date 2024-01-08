---
title: "Detection Engineering at 自宅"
emoji: "🏠"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security"]
published: true
---

年末年始に長い休みを取得できたので、2024年に会社で取り組もうとしている [Detection Engineering](https://zenn.dev/mizutani/articles/start-de-ubie) の取り組みを自宅で素振りしてみました。短い期間だったのでツール自体やドキュメントの整備など至らぬ点はいろいろありますが、ひとまずこの記事ではその内容についてご紹介します。

## モチベーション

今年取り組もうとしているDetection Engineeringを小さく試してみたかったという他にも、以下のようなモチベーションがありました。

### 1. 多数のデバイスがつながる自宅ネットワーク内の監視をしたい

その昔、自宅のネットワークに接続しているものといえばたかだかパソコン程度のものでした。どのようなデバイスが繋がっているかも把握しやすく、セキュリティの観点からも管理しやすい状況でした。しかし今では自宅にはスマートフォンやタブレット、IoTデバイスなどありとあらゆるデバイスが接続されています。正直自分も今すぐネットワーク内のデバイスを列挙しろと言われたら難しい状況です。これらのデバイスは基本的に外部からの接続は受け付けないようになっているものの、自宅ネットワーク内からは自由に通信が発生しており、完全に安全とは言えません。

また各デバイスが適切な状態であるかを管理するのも困難です。各デバイスがどのような通信を送受信しているか、どのようなデータを送受信しているか、どのようなポートを開けてどのようなサービスを受け付けているのか、などを把握するのは難しいです。さらにデバイスによっては脆弱性があったとしてもアップデートが行われないものもあり、そのようなデバイスがネットワーク内に放置されているということもありえます。このようなことから、最低限何らしらの形で自宅ネットワーク内の監視をしたいというモチベーションがありました。

### 2. 過去の取り組みの改善

奇しくも7年前の年末年始休みに [12800円で自宅や小規模オフィスのネットワークセキュリティ監視環境を構築する](https://qiita.com/m_mizutani/items/dc9988daab24050eb5a2) という取り組みをしたことがありました。しかし、このときはネットワークのログを収集して表示するなどのみで、セキュリティ分析や検知まではできていませんでした。

それから7年たった今、[クラウドサービスを活用した監視基盤](https://www.youtube.com/watch?v=qN5-v4NlKac)を構築した経験などもさせてもらったこともあり、今あらためて自宅ネットワークのセキュリティ監視の設計・実装をやったらどうなるかを試してみたいと思った次第です。

## 今回の目標

実際の Detection Engineering では多数のデータをかき集めて分析してセキュリティイベントの検出や調査をしますが、今回はシンプルに

**「自宅ネットワーク内部とリスクのある外部ホストとの通信を検出する」**

を目標に設定したいと思います。具体的にはネットワークのフローログ（通信の送信元と宛先の情報）を取得し、IoC（過去にセキュリティ侵害に関連したホストなどの情報）と突き合わせることで、自宅ネットワーク内部とリスクのある外部ホストとの通信を検出します。理由は以下の通りです。

- **とれるデータがネットワークのログぐらいしかない**: コーポレートセキュリティ観点でデバイス監視をやろうとする場合、MDM（Mobile Device Management）やXDR（Extended Detection and Response）などのサービスを利用することが多いです。しかし自宅ネットワーク内のデバイス管理にわざわざそういうサービスを利用するほどの導入・運用コストはかけられないと思います。なにより今回対象としているIoT機器などは自由にソフトウェアをインストールできないので、そもそもそういったサービスを利用することができません。そのため今回はネットワークのログを取得することになります。
- **ネットワークから取得できる情報も限られている**: 2024年現在、大多数のサービスがWebサービスとして提供されており、その通信はTLSで暗号化されています。そのためIDS（Intrusion Detection System）やIPS（Intrusion Prevention System）などパケットから通信内容を読み取れることが前提のセキュリティ監視装置はほとんど無力になりました。そのため今回は通信の送信元と宛先の情報のみから検知をします。
- **そもそも素振りなので最小限にする**: 拡張性は考慮しながら実装しますが、あくまで目標は小さく、最低限の機能を実装することにします。

## アプローチ

「ネットワークの通信先がIoCであるか」を判定する方法として最もシンプルな方法は、IoCのIPアドレスをネットワーク監視装置に登録しておく方法と思われるかもしれませんが、これはあまり現実的ではありません。IoCは日々更新されており、実際に攻撃に利用されてしばらく経ってから発見されることもあります。そのため、IoCのIPアドレスをネットワーク監視装置に登録しておくというアプローチでは、通信の発生とIoCの登録の時間差で見逃しが発生してしまいます。

ではどうするかというと、次のような2つのアプローチが考えられます。

![](https://storage.googleapis.com/zenn-user-upload/a0f87c322302-20240107.jpg)

どちらのアプローチもネットワークフローおよびIoC情報をDBに保存して非同期に突き合わせをできるようにします。パターン1はログとIoC情報を取得するタイミングで突き合わせを行います。パターン2はログとIoC情報を取得するタイミングで突き合わせを行わず、ログをDBに保存した後に定期的に突き合わせを行います。

どちらのアプローチもメリット・デメリットがあります。パターン1は検知までのレイテンシが短くなりますが、「取り込むデータを同時にチェックする」というタスクの仕組みはアーキテクチャがやや複雑化し、実装コストが高くなります。一方、パターン2は検知までのレイテンシが長くなりますが、データの取り込みは愚直にDBへの保存ができればよく、アーキテクチャはシンプルになります。特に既存のサービスの機能やツールで「ログにDBを保存する」という機能までは提供されているものもありますが、「ログを取り込むタイミングでIoC情報と突き合わせる」という機能はほぼないため、パターン2は比較的実装コストが低いとみなせます。

そのため、今後の拡張性なども考慮した上で今回はパターン2を採用することにします。

## アーキテクチャ

今回はGoogle Cloudのフルマネージドサービスをベースにして実装しました。パターン2のアプローチをより具体化したアーキテクチャは以下のようになります。

![](https://storage.googleapis.com/zenn-user-upload/b2048de2f98c-20240107.jpg)

基本は自宅ネットワークのフローログを取得してBigQueryに転送しつつ、IoC情報も定期的に取得してBigQueryに格納します。その2つを定期的に突き合わせて、IoCと通信が発生しているホストを検出します。検出されたホストについては、（とりあえず現状は）Slackに通知だけするようにしています。各パートの実装は既存ツール・サービスでも代用できますが、今回は一通り自分で実装をしました。実装した理由及び実装の詳細については後述します。

今回は検査するべき対象を自宅ネットワーク内のフローログに限定していますが、他のサービスや監視装置からのログもBigQueryへ格納さえできれば容易に拡張できるのがこのアーキテクチャのポイントです。例えば、Google Cloudの監査ログ、EDR（Endpoint Detection and Response）のログ、クラウドサービスの監査ログなどを追加していくことで、より広範囲な検知が実現できるようになっています。

Detection Engineeringの考え方は [前回の記事](https://zenn.dev/mizutani/articles/start-de-ubie) にも書きましたが、基本的にはセキュリティ監視の運用にソフトウェアエンジニアリングのベストプラクティスを持ち込むことです。そのため、今回の実装では以下のようなソフトウェアエンジニアリングのベストプラクティスを取り入れています。

- **コード化**: 検知ルール・対応ルールのコード化によって変更の履歴をGitとして残すことができるようになります。
- **自動テスト**: ルールが自動テストできるようになっていることで、ルールの変更によって検知が壊れていないかを容易にチェックできるようにします。
- **CI/CDの活用**: ルールの変更をCI/CDで自動的にデプロイすることで、ルールの変更を素早く本番環境に反映できるようにします。

この他にもコードレビューをできるようにしたり、変更承認をするためのワークフローを作ったり、などの工夫ができますが、今回は自宅用であることもあり、これらは省略しています。また、アラートの自動対応（いわゆるSOAR、Security Orchestration, Automation and Responseの機能）もDetection Engineeringで扱いたい領域ですが、検出の頻度が多かったりチームで対応するケースでなければあまり効果を発揮しないため、こちらも今回は最小限のものにとどめています。

### (1) ネットワークフローログの収集

![](https://storage.googleapis.com/zenn-user-upload/c4729bdf5838-20240108.jpg)

まずは自宅のネットワークフローログを収集します。私の自宅ネットワークはあまり凝った校正にはしていませんが、ルータだけ[こちらのファンレスミニPC](https://www.amazon.co.jp/gp/product/B07YBXS678)を利用しています。CPUはCeleron N2840、メモリは4GB、ストレージは128GBのSSDです。このPCにはUbuntuをインストールして利用しています。このミニPCはネットワークインターフェースを2つもつので、1つはインターネットに接続し、もう1つは自宅ネットワークに接続しています。

![](https://storage.googleapis.com/zenn-user-upload/8c2f60322435-20240108.jpg)
*弊宅PCルータ。かなり安定しており、かれこれもう2、3年はトラブルなく稼働してます*

今回はここにネットワークパケットキャプチャ用に作成したツール [devourer](https://github.com/m-mizutani/devourer) をインストールしています。キャプチャしたパケットからフローを集計して、その結果をBigQueryに直送します。

https://github.com/m-mizutani/devourer

この機能は[Packetbeat](https://www.elastic.co/jp/beats/packetbeat)および、[fluentd](https://www.fluentd.org/) で実現することもできます。今回、あえて自分で実装してみた理由としては、複数のツールを組み合わせたときにトラブルになると対応がやや面倒なのでワンバイナリで動かしたかったこと、そして久々に自分でパケットキャプチャのプログラムを書いてみたかったことです。もしこの構成を再現してみたいという人がいたら、素直にPacketbeat + fluentdの構成がおすすめです。

devourer は以下のような形式でBigQueryにフローログを格納します。これを(3)のチェックで利用します。

| Column name | Type | Description |
| --- | --- | --- |
| id | string | Unique ID of the network flow. |
| protocol | string | Protocol of the network flow. |
| src_addr | string | Source IP address of the network flow. |
| dst_addr | string | Destination IP address of the network flow. |
| src_port | int | Source port of the network flow. |
| dst_port | int | Destination port of the network flow. |
| first_seen_at | timestamp | Timestamp when the network flow was first seen. |
| last_seen_at | timestamp | Timestamp when the network flow was last seen. |
| src_bytes | int | Number of bytes sent from the source to the destination. |
| dst_bytes | int | Number of bytes sent from the destination to the source. |
| src_packets | int | Number of packets sent from the source to the destination. |
| dst_packets | int | Number of packets sent from the destination to the source. |
| status | string | Status of the network flow. |

### (2) IoC情報の取得

![](https://storage.googleapis.com/zenn-user-upload/c467fa9bd059-20240108.jpg)

次にIoC情報を取得します。IoC情報は提供サイトごとに全く異なる方式で提供されています。今回は以下の2つのサイトからIoC情報を取得しています。

- [abuse.ch](https://abuse.ch/) （JSONなどのフォーマットでファイルをダウンロードする方式）
- [OTX](https://otx.alienvault.com/) （APIを利用する方式）

こういった複数種類のサイトからIoC情報を取得する場合、それぞれのサイトに対して異なる取得方法を実装するのは面倒です。今回作成した [drone](https://github.com/m-mizutani/drone) というツールは各サイトの取得方法をある程度まで抽象化して、拡張をしやすいようにしています^[SIEM製品・サービスでは複数ソースからIoCを取り込む機能は良くありますがOSSなどで任意のDBに格納するようなツールはあまり見たことがありませんでした。もしご存じの方がいたらぜひ教えてください]。

https://github.com/m-mizutani/drone

このツールはIoC取得してBigQueryに格納するための手順を一元化するのに加え、過去のIoC情報を重複して格納しないようにする役割もあります。IoCは常に新しい情報が追加されていきますが、提供サイトでは過去のデータも提供していることが多いです。そのため、IoC情報を取得するたびにすべてのデータをBigQueryに格納してしまうと、重複して格納されてしまいます。サイトに寄っては数百MB単位のIoC情報を提供しているため、抑制をしないとそれなりのデータサイズになってしまいます。そのため、drone は過去に取得した日時をベースに、新しい情報のみをBigQueryに格納するようにしています。

BigQueryに格納されるスキーマはあえて各提供サイトごとに異なる形式にしています。これは、標準スキーマに落とし込むと元データの情報が欠落してしまうこと、そして同じスキーマにしたい場合は[Materialized View](https://cloud.google.com/bigquery/docs/materialized-views-intro)を利用した方が自由度が高く扱える、と考えたためです。

このツールはCloud Run jobsとして作成され、Cloud SchedulerからWorkflowsを経由して、定期実行されるようになっています。これはサイトごとに取得するためのタスクを分離しておいたほうが、失敗時のリトライがしやすくなるためです。ツール自体はワンバイナリで各サイトの取得方法を実装していますが、Workflowごとに異なる引数を指定させることで、1つのJobを使い回せるようになっています。

### (3) IoC情報とネットワークフローの突き合わせ

![](https://storage.googleapis.com/zenn-user-upload/cd7a900c4f6b-20240108.jpg)

このパートでやりたいことは至ってシンプルで、(1)で集めたネットワークフローと(2)で集めたIoC情報を突き合わせて、IoCと通信が発生しているホストを検出することです。これも(2)と同様にCloud Run jobsとして作成され、Cloud SchedulerからWorkflowsを経由して、定期実行されるようになっています。IoCとの通信が発生していた場合、これをアラート情報としてPub/Subに送信します。このアラート情報は(4)で利用します。

#### ツールの実装

BigQueryに投げたクエリの結果をPub/Subに流すだけなので、機能的に見ればわざわざツールを実装しなくてもWorkflowsだけで実現できます。今回、あえてツールを実装したのは、SQLを管理しやすくしたかったこと、そしてテストを自動化したかったことが理由です。

WorkflowsでBigQueryへのクエリを発行する場合、[一般的にはワークフロー定義内にSQL](https://cloud.google.com/workflows/docs/samples/workflows-connector-bigquery)を記述することが多いようです。短いクエリの場合はいいのですが複雑かつ長いクエリを管理するにはSQLとして解釈可能なファイルとして管理するほうが機械的なチェックやテストがしやすくエディタのサポートも受けられるなどの恩恵があります^[Cloud StorageやSecret Managerを利用するという方法もありそうでしたが、より煩雑になるかと思い避けました]。

自動テストをすることもDetection Engineering観点では重要な視点です。テストがあることによって変更を加えたときに検知が壊れていないかを確認できるようになります。これは変更に伴う安心感を与えつつ、より積極的な変更ができるようになります。検知のルールは、外的要因（攻撃の傾向の変化、新しい脆弱性の発見など）や内的変化（組織構造の変化やプロダクトのアーキテクチャ変更）によって常日頃から変化しつづけるものです。そのため、変化に対応できるようにルールの変更をしやすくすることは重要です。

このような要求を満たすため、ひとまず今回はクエリの発行とPub/Subへの送信、そして自動テストを実施できる [overseer](https://github.com/m-mizutani/overseer) というツールを作成しています。

https://github.com/m-mizutani/overseer

このツールは指定したディレクトリ内にある以下のようなメタ情報を含む `*.sql` ファイルを読み込み、順次BigQueryにクエリを発行します。

```sql:flow_logs_abusech_feodo.sql
-- title: Detect flow logs with IoC from abuse.ch Feodo Tracker
-- limit: 10
-- test: true, flow_logs_abusech_feodo.yml

WITH
  ioc AS (
  SELECT
    as_name,
    ip_address
  FROM
    `mztn-dep.drone.abusech_feodo` )
SELECT
  DISTINCT logs.src_addr,
  logs.dst_addr,
  logs.first_seen_at,
  ioc.as_name AS threat_name,
  ioc.ip_address AS ioc_addr
FROM
  `mztn-dep.devourer_home.flow_logs` AS logs
INNER JOIN
  ioc
ON
  logs.src_addr = ioc.ip_address
  OR logs.dst_addr = ioc.ip_address
WHERE
  first_seen_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
LIMIT
  10
```
https://github.com/m-mizutani/overseer-deploy/blob/main/queries/flow_logs_abusech_feodo.sql

`drone.abusech_feodo` が abuse.ch から取得したIoC情報が格納されているテーブルです。このSQL文はシンプルに過去2日間のフローログとIoC情報を突き合わせて、IoCと通信が発生しているホストを検出するものです。幸いというべきか、いまのところ検出されるホストはありませんでした。

#### テスト

BigQueryへのテストをどう実装したら良いかは最後まで悩んだのですが、ひとまずエミュレータを使ってみることとしました。

https://github.com/goccy/bigquery-emulator

このエミュレータはBigQueryのREST APIをエミュレートしてくれるので、テストのためにBigQueryを利用する場合に便利です。今回はこのエミュレータを利用して、テスト用のデータを流し込んだデータセット、テーブルを作成しています。テスト用データはYAML形式で記述することができるため、テストごとに必要なレコードを定義できます。簡単ではありますが、以下のような形式です。

```yaml:flow_logs_abusech_feodo.yml
projects:
  - id: mztn-dep
    datasets:
      - id: drone
        tables:
          - id: abusech_feodo
            columns:
              - name: as_name
                type: STRING
              - name: ip_address
                type: STRING
            data:
              - as_name: test1
                ip_address: 10.1.2.3
              - as_name: test2
                ip_address: 10.2.3.4
      - id: devourer_home
        tables:
          - id: flow_logs
            columns:
              - name: src_addr
                type: STRING
              - name: dst_addr
                type: STRING
              - name: first_seen_at
                type: TIMESTAMP
            data:
              - src_addr: 10.1.2.3
                dst_addr: 10.0.0.2
                first_seen_at: 0000-00-00T00:00:00Z
```

データ作成時に現在時刻を指定する方法がわからなかったため、`first_seen_at` は `0000-00-00T00:00:00Z` として、テスト実行時に置き換えるようにしています。テストは `overseer` の `test` サブコマンドで実行され、テストごとにテスト用データを読み込んだ `bigquery-emulator` を起動してクエリしています^[本当はbigquery-emulatorがGoライブラリとしても利用できるため完全にモック化しようとしたのですがビルドにCGOが必要であり、ビルド環境の問題やビルド時間などにいろいろ問題があったため、ひとまずサーバとして都度起動する形にしました]。先程のSQLファイルのコメントとして `-- test: true, flow_logs_abusech_feodo.yml` という記述があるのは、このテスト用データを指定するためのものです。先頭の `true` は「結果を得られるかどうか（得られなかったら未検知）」を意味しています。これをCLIで実行すると以下のようになります。

```
% overseer test -d queries/
13:58:51.901 INFO [test.go:23] Start test task="Detect flow logs with IoC from abuse.ch Feodo Tracker"
13:58:52.847 INFO [test.go:38] Test passed task="Detect flow logs with IoC from abuse.ch Feodo Tracker" file="flow_logs_abusech_feodo.yml"
```

テストが通ると `Test passed` と表示されます。逆にテストが通らない場合は非ゼロ終了します。

### (4) アラートの対応

先述の通り、今回は検知したアラートに関する対応は最小限の通知のみにとどめています。チームで対応する場合はチケット起票やアラート内容に応じた通知先の割り振り、追加情報の調査、そして場合によっては通信の遮断なども視野に入れられるでしょう。しかし今回はあくまでワンマン運用のため、そこまでは特に必要ありません。このあたりのツールの話は、また別の機会に書きたいと思います。

https://github.com/m-mizutani/alertchain

### (5) ルールの変更

Detection Engineeringで活用するソフトウェアエンジニアリングのベストプラクティスの1つがCI・CDかと思います。今回は(2)のdrone、(3)のoverseer、(4)のalertchainの3つのツールについて、GitHub Actionsを利用してCI・CDを実現しています。これによって、ツール自体の更新やルールの変更が自動的にデプロイされるようになっています。

通常これらのワークフローを公開する意味はないのですが、今回は試験的に試していることもあり以下のデプロイよりリポジトリを以下の通り公開しています。

https://github.com/m-mizutani/drone-deploy

https://github.com/m-mizutani/overseer-deploy

https://github.com/m-mizutani/alertchain-deploy

droneについてはただそのままCloud Run jobsにデプロイしているだけなのですが、overseerとalertchainについては、ルール・ポリシーを管理するためのリポジトリとしても活用しています。これによって、ルールの変更をGitHub上で管理できるようになっています。

またCI上でテストも実施できるようにしています。overseerはデプロイ用のイメージを作成する前にテストを実施しており、これが失敗するとデプロイ処理が中断されます。これはもうちょっと真面目にやる場合、defaultブランチを保護してPRを通すようにし、テストがPassした場合のみマージを許可するというようなワークフローでより厳格に運用することができます。

## 今後の課題

今回はあくまで素振りなのですが、本番に向けて実装をしていくに当たり以下のような課題があることに気づけました。これについては、2024年のあいだに取り組んでいきたいと考えています。

### IoC情報スキーマの標準化

もともとは各IoC情報サイトから得られた情報をそのままBigQueryに格納していましたが、これではIoC情報を突き合わせるたびにSQLを書き換える必要があります。最初はMaterialized Viewで統合するなどを考えていたのですが、データサイズや種類が多くなるに連れて実際にワークするのかを考慮する必要があります。

少なくともスキーマが別れているとIoC情報の種類が増えた場合に、ログの種類との組み合わせで管理するべきSQLの数が非線形に増えてしまいます。そのため、IoC情報のスキーマを標準化して、ログの種類との組み合わせで管理するべきSQLの数を減らすなどの工夫も検討したいと考えています。

### 検知用SQLの管理方法

今回用意したテストはあくまで検知の有無を確認するもので、検知されたホストが正しいかどうかを確認するものではありません。これは現状、テストなどに関するデータをコメント内のメタデータとして管理しているため記述力に乏しいのが一つの原因です。メタデータ内の情報を詳しくすると読み込む際のparserが複雑化してしまい、あまりそこに労力を割きたくありません。

これについては別途メタデータを管理するファイルを用意するか、あるいは別の方法で管理する必要がありそうです。それによってより記述力の高いテストを実行できるようにし、検知の有無だけでなくクエリの結果が期待さていかどうかまでを確認するようなテストができるようにしたいと考えています。これについては自分のBigQuery関連の知識（特にベストプラクティスなど）がまだかなり浅いということにも起因しているため、知識を深めるようにしていきたいと思います。

### デプロイ用リポジトリの整理

今回、デプロイ用のリポジトリを3つにそれぞれ分離しているのは、単純に順次作成したためです。これらを1つにまとめることで、よりシンプルに管理できるようにすることが期待されます。これらを一つに統合することで、アップデートの依存関係なども同期的に管理できるようになります。

また今回は試験的にいろいろなリソースを作成したり破壊したりということを繰り返していたのでGoogle Cloudのサービスは基本的にコンソールから操作していました。真面目にやる場合、リソースの変更履歴管理や似たようなリソース作成の際のモジュール化の観点でやはりIaC（Infrastructure as Code）を利用するべきだと思います。これについても本番でやる際などには真面目に取り組んでいきたいと考えています。

## まとめ

ということで、年末年始も十分素振りをしたところで、2024年もやっていきたいと思います。引き続き、本年もよろしくお願いいたします。

