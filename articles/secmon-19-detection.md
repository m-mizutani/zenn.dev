---
title: "実践セキュリティ監視基盤構築(19): アラート検知の実装要点"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の19日目です。

今回はアラート検知の実装について解説します。このアドベントカレンダーでは、BigQueryに定期的にクエリを発行してアラートを検知する、いわゆるバッチ型のアラート検知を前提としていますが、ストリーム型のアラート検知もあります。それぞれの実装方法のポイントについて解説します。

# アラート検知の処理系

アラート検知の処理系は大きく分けて、発生したログデータを逐次的に受け付けて検知するストリーム型と、定期的にクエリを発行して検知するバッチ型があります。今回は自分で実装することを前提にしていますが、既存のSIEMなどもいずれかの方法で実装されていることが多いです。それぞれの特徴を説明します。

## ストリーム型

発生したログを1件ずつ検査し、あらかじめ定義されたルールにマッチするかどうかを判定します。ログはメッセージングサービス（例: Pub/Sub）を経由して送信されてきたり、syslog、logstash、fluentdやHTTPのAPIを経由して送信されてくるものなど様々ですが、基本的には到着したログを次々に処理していきます。

この実装方法の最大の利点は遅延が小さいことです。ログが到着した段階で検知を行うため、ログの取得から検知までの遅延がほとんど発生しません。そのため、緊急度の高いアラートを検知し、即座に対応するためには適しています。

一方でストリーム型の実装は複数のログに跨ったアラートを検知するのが難しいという弱点があります。アラートの検知は1つのログだけでなく複数のログを組み合わせて検知するものも多くあります。ストリーム型の実装ではログを逐次的に処理していくため、1つのログに出てくる特徴だけでアラートを検知するのは問題ありませんが、ログ間の関係を表現しようとするならその情報を保持する必要があります。

このためのアプローチは大きく分けて以下の2つになります。

![](https://storage.googleapis.com/zenn-user-upload/76bf17bdcfbb-20241210.jpg)

### 💡 (パターン1) 短期的な記憶領域を用意し状態を保持する

定常的に稼働しているインスタンスなどであればメモリ上に、サーバレスであればCloud Firestoreなどのデータベースに状態を保持する方法です。これによってログの出現数、関連ログ観測の有無、特定のログの出現頻度などを記録し、それを元にアラートを検知します。

この方法は状態を維持・管理する実装が比較的複雑になります。例えばあるログが一定期間内に発生した件数をカウントする場合、カウントする数値をそのまま加算で保持するとします。そのあと時間が経過したら過去のログは対象期間から外れるため、その分を減算しなければなりません。

![](https://storage.googleapis.com/zenn-user-upload/6905165d12ce-20241211.jpg)

これが数件であればログ毎の発生時刻を全て記録しておけばいいのですが、数十万件、数百万件となると記憶領域を圧迫してしまいます。それを回避するためにはタイムスロットを設けて、そのスロット内に発生したログの数をカウントするなどの工夫が必要です。

状態遷移のルールを保つ場合はステートマシンを実装すれば良いのですが、ここで難しいのが全てのログが一律の遅延で到着するわけではない、ということです。ログの提供元によって遅延はバラバラになりますし、同じ提供元のログでも遅延が安定しないこともあります。単純なステートマシンで状態遷移を実装すると、後から到着したログが先に到着したログよりも前の状態に必要だった、ということもあり得るため、その辺りの実装には注意が必要です。

### 💡 (パターン2) ログデータベースから都度関連するログを取得する

定常的に稼働しているインスタンスなどであればローカルストレージに、サーバレスであればデータウェアハウスにログを保存し、ルールの起点となるログを観測するたびに関連するログを取得し、その結果を元にアラートを検知します。

この方法はパターン1に比べるとシンプルに実装できます。ルールに関連したログを観測したタイミングで過去に観測されたログを全て取り出し、そのログの集合を集計、分析、検査すればよくなります。ログの遅延がバラバラだったとしても必要なログが全て揃った段階で、最も遅延を小さくして検知ができます。

一方でこの手法の問題はコストになります。検査対象のログが到着するたびにデータベースにクエリをすることになるため、ルールに関連したログが多く到着するほどデータベースの負荷が高まります。BigQueryなどのサービスの場合はスキャンした容量に応じて課金が発生するため、頻繁にクエリを発行すると使用料金が大幅に上昇するおそれがあります。

### ⚠️ ストリーム型処理実装における注意点（パフォーマンス）

パターン1、2のどちらにも言えることですが、ストリーム型でアラート検知をする場合はパフォーマンスを保つことが重要です。ストリーム型は遅延を小さくすることが目的であるため、処理が遅くなると遅延が大きくなってしまい恩恵が小さくなってしまいます。

セキュリティ監視基盤に利用するログの流量は通常安定していますが、環境の変化やイベントの発生によって急激に増加することがあります。そのような事態になった場合、速やかに処理可能なパフォーマンスを向上させるための対策を講じておくことが重要です。

ここで先程述べた複数ログに跨ったアラート検知の問題が再び出てきます。どちらのパターンもインスタンスの内部メモリやローカルストレージを利用するほうがコスト・実装難易度のどちらからみても有利ですが、一方でその構成の場合はスケールアップしかできなくなります。インスタンス内部のメモリやストレージはインスタンスごとに紐づけされるため、この構成でスケールアウトしようとしてただ横に並べただけだと異なる状態やデータを持つインスタンスが増え、検知が正常にできなくなるでしょう。スケールアップは比較的簡単にできますが早い段階で限界がくることがあるため、最初からスケールアウトを意識して設計することが重要です。

## バッチ型

アラート検知実装のもう一つの方法はバッチ型です。バッチ型は定期的にデータウェアハウスにログをクエリして検索や集計を行い、その結果を元にアラートを検知します。ストリーム型と比べると遅延が大きくなりますが、その分実装がシンプルになるというメリットがあります。

### 定期クエリの実装

バッチ型アラート検知のもっともシンプルな実装方法は、定期的にクエリを発行してその結果をそのままアラートとして取り扱うことです。Google CloudではSDKを使ってクエリの呼び出しを実装したものをCloud Run、あるいはCloud Functionにデプロイし、Cloud Schedulerで定期実行することで実現できます。

さらにシンプルに実装したい場合はWorkflowsを使っても良いでしょう。Workflowsはクエリの実行とその結果を処理するためのステップを定義することができるため、クエリの実行とその結果を処理するためのステップを定義することができます。

https://cloud.google.com/workflows/docs/samples/workflows-connector-bigquery

アラート検知の後段にあたるアラート対応（通知など）に検知結果を渡す際、JSON形式にしたいということであれば `TO_JSON_STRING` のような関数を使ってJSON形式に変換することができます。これによってWorkflowsの定義だけでアラート検知処理を完結させることもできます。

https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions#to_json_string

しかし、いくつかの理由によりこの実際の運用には適さないこともあります。詳しくは [アラート検知実装における要点](#アラート検知実装における要点) の節で述べます。

### 実行するクエリの時間指定

バッチ型のアラート検知では一定期間のログをまとめて処理するため、その「一定期間」を表すための時間範囲が必要となります。この期間は現在時刻から遡って直近のN時間、直近のN日などを指定すれば良いように思えますが、実際にはそのように単純に指定することができません。

- ⚠️**ログが到着するまでの遅延がある**: ここまでの説明の通り、ログ提供元の問題やセキュリティ監視基盤のパイプラインの問題で、ログの発生時刻とログがクエリ可能になる時刻にはズレが生じます。そのため、現在時刻から遡って直近N時間をクエリすると、まだログが到着していないログは無視されてしまいます。
- ⚠️**実行時刻に誤差がある**: 一方でスケジューラーによってクエリが実行される時刻にも誤差が生じることがあります。時刻指定をする場合でも、スケジューラー側の都合での遅延や、タスクの起動にかかる時間などが考慮される必要があります。

これらを考慮しつつ重複を排除するようなクエリを実行するためには、現在時刻を分や時間単位で切り捨て、その結果からさらに一定期間前の範囲のデータを取得するようなクエリを実行する必要があります。例えば1時間単位でアラート検知をする場合、BigQueryの場合は以下のようなクエリを実行することで現在時刻から遡って直近1時間のデータを取得することができます。

```sql
SELECT *
FROM your_table_name
WHERE timestamp >= TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR) - INTERVAL 1 HOUR
  AND timestamp < TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR)
```

このクエリを想定される遅延時間に応じて実行時刻を調整します。例えば10分以内にログが到着することがある場合、クエリを実行する時刻を毎時10分に設定することで、期待するログが到着してからクエリを実行することができます。

### バッチ型処理実装における注意点（コスト・負荷の抑制）

バッチ型のアラート検知はデータウェアハウスに保存されたログにクエリしますが、その際にはコストや負荷を抑制するための工夫が必要です。自分たちで管理しているデータウェアハウスの場合は、クエリの実行による負荷が他のクエリに影響を及ぼすことがあります。一方、BigQueryやAmazon Athenaなどのマネージドサービスではスキャンしたデータの容量に応じて課金が発生するため、クエリの実行によるコストに注意が必要です。

クエリに対するコストや負荷の最適化では、ログデータベースの設計の節でも述べた通りパーティションを活用するのが有効です。特にログデータの場合、原則としてほぼすべてのデータが「ログの発生時刻」という時間情報を持っているため、この情報をパーティションキーにすることでクエリの対象範囲を限定することができます。これはマネージドサービスのデータウェアハウスだけでなく、商用のSIEMなどでも活用されている手法です。

パーティションを利用したクエリの最適化をする際には、パーティションがどの単位で設定されているかが重要です。例えばBigQueryの場合、時刻のパーティションは時間、日、月の単位で設定することができます。クエリの対象範囲が1時間単位であれば、クエリによるスキャン範囲も1時間単位で指定することができます。しかし日単位でパーティションを設定している場合、クエリの時間を1時間単位で区切っても1日分のデータをスキャンすることになります。このようにパーティションの設定単位によってクエリの最適化の方法が変わります。

これはどのくらいの周期でクエリを実行したいかにも大きく影響します。例えば1時間ごとにアラート検知をしたいにもかかわらず、パーティションが日単位で設定されている場合、1時間ごとにクエリを実行すると1日分のデータをスキャンすることになります。この場合、時間単位のパーティションを設定している場合に比べ、コストや負荷が10倍以上になると考えられます。そのため、クエリの実行周期とパーティションの設定単位については事前によく検討しておくことが重要です。

今回のアドベントカレンダーで主に利用するBigQueryには、その他にもコスト最適化のアプローチが以下で説明されているので、参考にしてください。
https://cloud.google.com/blog/products/data-analytics/cost-optimization-best-practices-for-bigquery

# アラート検知実装における要点

アラート検知の実装においては、ストリーム型とバッチ型のどちらを選択するかによって実装の要点が異なります。それぞれの実装方法における要点を以下にまとめます。

## テスト可能性

今回構築しているセキュリティ監視基盤ではソフトウェアエンジニアリングにおけるベストプラクティスをなるべく重視していますが、なかでも検知ルールのテスト可能性は非常に重要視すべきポイントです。ルールの設計の節でも説明しましたが、アラート検知のルールは単純な単一ログの検査だけでなく、複数のログを組み合わせて検知するようなルールもあります。このようなルールに対してテストができることで、以下のようなメリットがあります。

- ✅️**新たに記述したルールの正しさを確認できる**: ルールとはすなわちロジックであり、これが正しく動作するかを手軽に確認できることは非常に重要です。期待した動作になることを確認できることで、自信をもって本番環境にデプロイすることができます。
- ✅️**既存のルールの変更に対する影響を把握できる**: ルールは継続的に変更されるものです。その際に既存のルールに影響が出ないかを確認することができると、変更に対するリスクを軽減することができます。

検知ルールに対する非常に重要な考え方として、**ルールは常に更新し続けなければならない**ということがあります。一度設定したらそのまま放置しておくことはできません。

- 📌**新たな脅威への対応**: 新しい脅威は日々発生しており、検知したい対象は増えていく傾向にあります。これは新たな攻撃手法の登場や脆弱性の発見などによる外的要因だけでなく、組織の体制が変わったりビジネスのフェーズが変わって組織の抱えるリスクが変化した、というケースも多々あります。
- 📌**誤検知への対応**: 脅威によって引き起こされる事象だけを正確にルールで表現するのは困難であり、運用をする中では必ず誤検知が発生します。誤検知は人間が見て判断すれば良いとする運用方法もありますが、それでは認知負荷が高まる一方となり、運用が破綻してしまいます。そのため日々の運用ではこれを地道に取り除いていく必要があり、そのためにもルールを更新する必要があります。

実環境そのものに対してテストをするというのも可能ですが、工程が複雑であったり準備に時間がかかるなどの観点からそれだけでは不十分だと考えます。それをカバーするため、単体テストのような形で手軽かつ高速に検証をできる仕組みを用意することが重要です。

テスト可能性という観点では、実装がテストの仕組みを提供できるだけでなく、テストが容易に実施できる必要があります。そのためには以下のような要素が重要です。

- ✅️**テストデータの用意**: テストを行うためのデータを容易に用意、組み込めることが重要です。テストデータの用意が難しい場合、テストを行う頻度が下がり、その結果テストの効果が薄れてしまいます。
- ✅️**テストの自動化**: テストを手動で行うことは、テストの頻度を下げる原因になります。そのため、テストを自動化することが重要です。自動化されたテストは継続的に実行されるため、変更に対する影響を素早く検知することができます。
- ✅️**テストの実行時間の短縮**: テストの実行時間が長いと、テストを実行する頻度が下がります。ルールを更新しているときは繰り返し実行して検証するということもあるので、テストの実行時間が短縮できると有利です。

## ルールの記述性

ルールの表現力を含む記述性も重要な要素です。セキュリティ監視基盤は運用を始めると検知ルールがもっとも変更される部分になり、例外などのルールが増えていきます。そうなった場合、似たようなルールをまとめたり、ルールにでてくるデータを構造化して管理するなどによって、リファクタリングをしていくことになります。これによってルール全体の見通しが良くなったり、さらなる変更をする際にも迅速に対応できるようになります。

ルールの記述性を高めるためには、以下のような要素が重要です。

- ✅️**ルールの分割**: ルールを小さな単位に分割することで、ルールの再利用性を高めることができます。また、ルールの分割によってルールの見通しを良くすることができます。
- ✅️**ルールの構造化**: ルールにでてくるデータを構造化することで、ルールの記述性を高めることができます。例えば、ログのフィールド名や値を変数として定義しておくことで、ルールの見通しを良くすることができます。
- ✅️**ルールのバージョン管理**: ルールのバージョン管理を行うことで、ルールの変更履歴を管理することができます。これによって、ルールの変更に対する影響を把握することができます。

今回のアドベントカレンダーではバッチ型でBigQueryを使うため、SQLクエリが必ずルールの一要素になります。SQLの場合ルール（クエリ）を分割したり、テキストベースなのでバージョン管理はしやすいですが、構造化についてはやや苦手であるという特徴があります。SQLをそのまま利用する場合は、その点について注意が必要です。

## アラート対応との分離

既製のSIEMなどではアラート検知とアラート対応が一体化していることが多いですが、アーキテクチャの節でも触れた通り今回のセキュリティ監視基盤ではアラート対応との分離を推奨しています。これは取り扱うアラートがこの検知システムから発出されるものだけでなく、外部のシステムなどからも発生するアラートも取り込みたいためです。

外部からのアラートをログとして扱い、それを検知することでアラート対応のパイプラインに流すという方法をとることもできます（既製SIEMなどではそのアプローチを取るものが多いです）。しかしこの場合、アラート対応のテストをしたい場合にわざわざ検知のパイプラインを通す必要があり、テストの手間が増えてしまいます。また、アラート対応のテストを行う際には、検知とはわけることができるため、今回のアーキテクチャでは実装の分離を推奨しています。

# どの処理系を選ぶか

アラート検知の処理系を選ぶ際には、以下のような観点を考慮することが重要です。

- 📌**アラート検知できるまでの遅延**: 検知にかかる遅延を小さくすることが重要であれば、ストリーム型の処理系を選択することが有利です。一方で遅延が大きくても問題ない場合はバッチ型の処理系を選択することが有利です。
- 📌**複数ログによるアラートの重要性**: 複数ログに跨ったアラート検知を積極的に行いたい場合は、バッチ型の検知を利用するのがおすすめです。一方、単発のログで重要なアラートを検知できるユースケースが多いという場合はストリーム型で問題ないでしょう。
- 📌**運用負荷**: ストリーム型の処理系はリアルタイムで処理を行うため、運用が複雑になることがあります。特に障害が発生した場合のリカバリはとても面倒です。一方でバッチ型の処理系は定期的に処理を行っており、リトライもしやすいため運用が比較的容易と言えるでしょう。

一方で、以下の点はケースバイケースのため一概には言えませんが、考慮するべきポイントです。

- ❓**コスト**: ストリーム型の処理系は遅延を小さくするためにリアルタイムで処理を行う必要があり、そのためコストがかかることがあります。一方でバッチ型の処理系はスキャン量に応じてコストがかかるため、これらはそれぞれで動かすルールや流量などによってどちらが有利かは変動します。

ここまでストリーム型とバッチ型を対比するように議論してきましたが、もちろんこれらを併用するという方法もあります。例えばストリーム型で単発ログかつ低遅延で検知したいアラートを対応し、それでカバーできないアラートをバッチ型で定期的に検知する、というアプローチです。これは対応力の高いアプローチですが、処理系を2つ運用することになるため運用負荷は増えます。セキュリティ監視基盤の運用体制を考慮して、どちらかの処理系か、あるいはハイブリッドなアプローチかを選択することが重要です。

# まとめ

アラート検知の実装においては、ストリーム型とバッチ型のどちらを選択するかによって実装の要点が異なり、必要に応じて選ぶと良い、ということを解説しました。次回はバッチ型をベースとしたアラート検知の実装例について紹介したいと思います。