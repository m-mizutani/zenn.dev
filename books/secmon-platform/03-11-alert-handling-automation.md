---
title: "🛠️ アラート対応自動化の実装要点"
---

前回に引き続き、アラート対応の自動化におけるポイントを解説します。

# アラート対応自動化の実装方針

## SOAR is dead?

アラート対応の自動化といえば、[SOAR（Security Orchestration, Automation and Response）](https://www.gartner.com/en/information-technology/glossary/security-orchestration-automation-response-soar)が思い浮かびます。これは2017年ごろにGartnerが提唱した比較的新しい概念で、セキュリティ監視からアラート対応、インシデント対応を自動化するためのプラットフォームです。当初はアラート・インシデント対応の全てを自動化できると期待されていましたが、完全な自動化は難しいという見方[^Gorka][^darkreading]が広がり、GartnerのHype Cycle for Security Operations 2024では幻滅期に位置付けられています。

SOARの期待が外れた理由はいくつか考えられます。

- ⚠️ **例外ケースや対応パターンが多い**: よく発生する手続きのみを自動化する場合は効果的ですが、細かく頻度が低い手続きまで自動化しようとすると、効率化と運用コストが逆転してしまいます。
- ⚠️ **重厚なフレームワークは過剰**: 自動化自体は効果がありますが、SOARという独立のプラットフォームを導入する必要が必ずしもない場合があります。SIEMなどの別コンポーネントに同等の機能が組み込まれていることもあり、既存のワークフローオーケストレーションツールやチケットシステムを活用することで十分な場合もあります。

これらのことから、自動化そのものへの需要はあるものの、SOARという製品・サービスをあえて組み込む必要はないのではないか、という考え方があるようです。

[^Gorka]: SOAR is dead, long live the SOAR, https://gorkasadowski.medium.com/soar-is-dead-long-live-the-soar-3af6efed730b
[^darkreading]: https://www.darkreading.com/cybersecurity-operations/soar-is-dead-long-live-soar

## 今回のアプローチ

SOARという独立したプラットフォームに依存する必要はないという考え方が広まっていますが、今回はあえて独立したアラート対応のワークフローを実装します。その理由は以下の通りです。

- **内製することが前提であるため、どこに実装しても開発コストは変わらない**: SOARが不要とされる理由の一つとして、SIEMなどにすでに機能として組み込まれているため、別途SOARを導入する必要がないという考え方があります。しかし今回は全体的に自分たちで実装するため、機能としてはどこかしらに実装する必要があり、開発コストは大きくは変わりません。
- **外部からのアラートも受け付ける**: 今回のアーキテクチャでは外部システムで検知されたアラートも取り込んで処理します。その場合、アラート対応のワークフローが独立していることで、外部システムとの連携がしやすくなります。

もちろん、独立したワークフローにすることで運用負荷が高くなることを懸念し、アラート検知機能と密結合した機能として実装するというアプローチもあります。この方針については各組織ごとに検討する余地があると考えられます。

# ワークフローの実装ポイント

では、ワークフローの実装においてどのようなポイントがあるのかを見ていきましょう。

## ✔ 柔軟な分岐とロジックの表現

アラート対応のワークフローは、アラートの内容によって処理が変わることが多いです。例えば、アラートの内容によっては通知だけで済むものもあれば、トリアージや暫定処置が必要なものもあります。さらにアラートの内容や時間帯に応じて通知先を変えたり、アラートの内容によってはチケットを作成したり、外部システムに対して何らかの処理をするなど、実際の運用をするといろいろなパターンが出てきます。このような条件の組み合わせは柔軟に設定できると便利です。

条件分岐ではなく全てのパターンに応じたワークフローを実装することも考えられますが、その場合はワークフローの数が多くなり、管理が複雑になり、メンテナンスの負担が大きくなるという懸念があります。

また、今回のアラート対応のワークフローは外部システムからのアラートを受け付けるため、外部システムからのアラートで不要なものを無視する機能も必要です。外部システム側でフィルタリングすることもできる場合もありますが、それができない場合はワークフロー側でフィルタリングする必要があります。このためにも柔軟な分岐機能やロジックの表現能力が求められます。

## ✔ テスト可能性・自動化

他のコンポーネントの実装でも再三触れてきましたが、アラート対応のワークフローもテスト可能性が重要です。アラート対応に柔軟な判断ロジックを入れるということは、そのロジックが期待通りに動作するかを検証することが必要です。そのためにテストができるフレームワークを用意しておくことは重要です。

特にアラート対応のワークフローは外部システムに対してリクエストを送る、あるいは応答を受け取り、それに応じて処理を行うといった機能が含まれることが多いです。そのため、E2Eテストをするためにはテスト用の外部システムを用意しなければなりません。単純に外部システムと接続するだけならまだいいですが、こちらからの入力に対して期待した出力をするように外部システムを制御するのは手間がかかる場合があります。もちろん結合テストは一定必要ですが、常に結合テストを行うのは手間がかかるため、擬似的な入出力を利用者が定義できるモックのような仕組みを用意しておく必要があります。

## ✔ アラートの集約・紐づけ

アラート対応を自動化するにあたって重要な機能に、複数アラートの集約や紐づけがあります。検知のシステムやロジックにもよりますが、あるときアラートが一度に大量発生することがあります。これは必ずしも攻撃によるものではなく、システム状態や環境の変化、（外部セキュリティシステムの）検知ルールの変化などが原因になることも多いです。

アラート対応は外部システムに干渉しますが、その中にはせいぜい数分に1度程度リクエストを受け付けて処理をすることを前提にするようなものもあります（例：インスタンスのバックアップ作成、追加の監視機能有効化など）。大量のアラートが発生するとそのような外部システムに過負荷をかけ、最悪の場合は別の障害を引き起こす恐れがあります。

また、外部システムに関係なく、単純にアラートの数が多いと担当者やセキュリティアナリストが捌く手間が大きくなってしまいます。これらをうまく集約することで対応する人物の手間と認知負荷を軽減し、適切な対応を促すことができます。

アラートの集約や紐づけをするアプローチは大きく2つに分けられます。

- **逐次型**: アラートを受信したらその都度、集約や紐づけができるかを判断して処理するアプローチです。すでに到着しているアラートと比較して類似点を探すことはできますが、未来に到着するアラートについてはわからないため、その後のアラート次第で結果が変わる可能性もあります。そのため、逐次で処理するためには事前に何をキーにするかなどの知識を与えておくのが望ましいです。
- **一括型**: アラートが到着してもすぐには対応せず、ある程度アラートが出揃った段階でまとめて集約・紐づけを試みるアプローチです。集約が完了するまで遅延があり、通知のように低遅延で処理するものについては乱発してしまう可能性がありますが、それを許容できるなら事前知識無しでもある程度は適切に集約・紐づけをしてくれるようになります。

# ワークフローの実装のアプローチ

では実際にどのようにワークフローを実装できるのかを整理したいと思います。ワークフロー全体を実装する際、個別のワークフローとは別に共通する機能もあります。例えばワークフローの起動を制御する、設定値を読み込む、エラーハンドリングをする、実行ログを出力するなどです。これらの共通機能を冗長に実装しないためにも、ワークフローそのもののロジックと全体制御の実装を分離できる形にしておくのが望ましいでしょう。

ここからは各ワークフローのロジックの実装方法について議論します。

## ⚒️ プログラミング言語で構成

まず思いつく方法は一般的なプログラミング言語によってロジックをそのまま記述することです。各種プログラミング言語に用意されているプラグイン的な機能を活用することによって、ワークフローのロジックと全体制御を切り離し、任意のロジックを追加しやすくすることも容易でしょう。プログラミング言語を直接利用する場合、各言語ごとにテスト用のフレームワークが用意されていることがほとんどで、それを利用してモックによるテストなども簡単に実装できます。

プログラミング言語を使う際の注意点は、多くのプログラミング言語の自由度が高いことです。特に外部入出力（例えばファイルI/Oやデータベース）を利用し始めると、途端に処理やテストが複雑化します。これは適切なガイドラインや制約を設けて制御することもできますが、筆者の経験上ではプログラミング言語を用いた場合に全体の見通しが悪くなってしまうことがしばしばありました。

## ⚒️ 独自DSLを定義

プログラミング言語を使う場合の問題点を克服するために、独自のDSL（Domain Specific Language）を定義してワークフローを記述する方法もあります。DSLは特定のドメインに特化した言語で、そのドメインにおける問題を解決するために設計されます。そのため機能を制限することができ、ワークフローの記述が簡単になるというメリットがあります。

DSLを使う場合の課題は実装の手間がかかることです。ワークフローを表現するためのDSLを作る場合、文法の設計だけでなく、そのDSLを解釈するためのエンジンを実装する必要があります。さらに柔軟な分岐の条件などを表現するためには、分岐そのものではなく条件に使うデータを加工したりする仕組みが求められます。わかりやすい例でいうと、文字列を比較する場合に単純な一致だけでなく、前方一致や後方一致、正規表現だけでなく、2つの文字列から一部の文字を切り出して比較する、といった条件判定などです。さらに構造化データに対してそのような処理をしたくなることもあり、DSLの設計に大きな工数が必要になるでしょう。

## ⚒️ ワークフローオーケストレーションサービスの利用

プログラミング言語の利用と独自DSLの利用の中間に位置する方法として、ワークフローオーケストレーションサービスを利用する方法があります。例えばクラウドサービスプロバイダーが提供するサービスとして、AWS Step FunctionsやGoogle Cloud Workflowsなどがあります。これらのサービスはワークフローを定義するためのDSLを提供しており、それを使ってワークフローを記述することができます。

ワークフローオーケストレーションサービスを利用する場合のメリットは、DSLの設計やエンジンの実装を自前で行う必要がないことです。また、クラウドサービスとして提供されているため、スケーラビリティや耐障害性などの面でも優れていることが多く、全体的に実装のためのコストが低くなることが期待できます。

一方のデメリットはテストがしにくい点です。例えばAWS Step Functionsの場合、具体的な処理はLambda関数などで実装することになりますが、ローカルテストでモックをする場合はそのLambda関数ごとモックすることになります。純粋なステート管理だけをテストすることは可能ですが、Lambda関数内にも何らかのロジックを保つ場合に最終的な外部サービスの呼び出し部分をモックするのは難しくなります。Google Cloud Workflowsについてはそもそもテストの仕組みを持っておらず、動作確認をするには実際に実行する、あるいはモック用のサーバを別途用意するなど、あまり手軽には実行できないという課題があります。

# まとめ

今回構築するセキュリティ監視基盤の要件などを踏まえて、アラート対応の自動化の仕組みを実装するにあたって考慮すべきポイントをまとめました。アラート対応は全て自動化することを目的にするのではなく、自組織やチームの状況を踏まえつつ、対応にコストがかかっている部分を「エンジニアリング」して効率化していくアプローチが望ましいのではないかと考えます。

次回はアラート対応の自動化の実装例を紹介します。