---
title: "実践セキュリティ監視基盤構築(21): アラート対応の設計"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の21日目です。本アドベントカレンダーではアラート対応の自動化、エンジニアリングまでを取り上げますが、まずはアラート対応とはどういうものか、どう設計するべきかという観点について議論します。

# 「アラート対応」の位置づけ

まず本アドベントカレンダーにおける「アラート対応」の位置づけについて整理します。情報セキュリティにおいて問題を検知したあとの対応としては「インシデントレスポンス」が有名です。ただ、インシデントレスポンスという言葉はもともとかなり広い意味を持っており、例えば[NISTのSP 800-61 Computer Security Incident Handling Guide](https://csrc.nist.gov/pubs/sp/800/61/r2/final)ではそもそもセキュリティ監視全般がインシデントレスポンスの一部として扱われています。それもあって、今回はインシデントレスポンスという言葉を使わずに「アラート対応」という言葉を使っています。

ただ今回の解説での整理として、「アラート対応」と「インシデント対応」は区別しています。「アラート対応」は、アラートが報告されたときにそれが組織に対して影響を及ぼすかどうかを判断するまでの過程を指すこととします。一方で「インシデント対応」は、アラートが組織に対して影響を及ぼすと判断された場合に、その影響を最小限に抑えるための対応を指すこととします。実務においてはこの2つの過程は連続しており、明確に境目を区切ることは難しいですが、それぞれの過程において求められる役割というのは明確に異なります。

今回のアドベントカレンダーでは「インシデント対応」には触れませんが、「アラート対応」については、その設計や自動化について解説します。

# アラート対応の種類

具体的にアラート対応でやるべき処理について整理したいと思います。

## 📋 通知・周知

まずはアラートが発生した際に、関係者に通知を行うという処理です。アラートを検知したとしてもそのまま放置していては意味がないため、迅速に関係者に通知することが重要です。

現代において通知の方法は様々です。少し前まではメールと電話＋SMSが主流でしたが、最近ではSlackなどのチャットツール・サービスがビジネスコミュニケーションでも活用されており、それを利用することも可能です。また、PagerDutyやOpsGenieなどのアラート管理サービスを利用することもあります。特にアラート管理サービスでは条件に応じて通知方法や通知先を選ぶことができるため、柔軟な通知設定が可能です。

## 📋 トリアージ

アラートが発生した際に、そのアラートが組織に対して影響を及ぼすかどうかを判断する処理です。アラートが発生したからといって、それが組織に対して影響を及ぼすかどうかは必ずしも明確ではありません。悪意のない挙動を誤検知してしまう場合もあるし、悪意のある攻撃だったが失敗して影響がなかった、という場合もあります。そのため、アラートが発生した際には、そのアラートが組織に対してどのような影響を及ぼすかを判断する必要があります。トリアージでは影響の有無だけでなく、影響度の高さや対応の優先度も判断することが求められます。

トリアージは報告されたアラートに含む情報だけでなく、関連する情報の収集が必要となる場合が多いです。関連する情報は以下のようなものがあります。

- 📌 **アラートに登場した要素に関するログ**: 主体（subject: 例えばIPアドレス、ユーザ名、ファイル名など）やリソース（object: 例えばファイル、データベース、サーバなど）に関するログデータを、データウェアハウスから取出します。
- 📌 **アラートに登場した要素に関する外部情報**: 主に主体について、レピュテーション情報やIoC（Indicator of Compromise）として記録されてないかを確認します。
- 📌 **アラートの要素の現状調査**: 主にリソースについて、現在の状況を直接的・間接的に確認します。例えばインスタンスだった場合、プロセス・ファイルシステム・ネットワークの状況などを確認します。特殊なツールを用いる場合もあります。
- 📌 **関係者への確認**: 主体が内部のユーザだった場合、その挙動が意図的だったのかや、何か関連した作業をしていたのかなどを確認します。

これらの情報を必要に応じて収集しながら、アラートの影響度を判断することが求められます。

## 📋 暫定処置

アラートがまだ組織に影響を及ぼすものであったかを判断する前の状況であっても、その影響が大きい可能性がある場合には暫定処置をすることがあります。例えばインスタンスや端末への侵入が疑われる場合に、一時的にそのインスタンスや端末へのアクセスを遮断したり、その時点でのバックアップを作成してデータの保全や証拠の確保という処置が考えられます。

先述した通りこの対応は投機的であり、実際には影響を及ぼさない可能性も考慮しなければなりません。そのため、バックアップ作成などの非破壊的対応は比較的安全ですが、アクセスを遮断するなどの破壊的対応は慎重に行う必要があります。特に実運用環境での対応は、アクセスの遮断が同系列のシステム、あるいは他のサービスに影響を及ぼす可能性があり、より慎重さが求められます。

## 📋 アラート管理

アラートが発生した際に、そのアラートに関する情報を記録する処理です。そのアラートが今どういうステータス（未着手、調査中、調査終了：影響なし、調査終了：影響あり、など）なのかだけでなく、トリアージや暫定処置をするにあたっての経過の情報や、ステークホルダーとのコミュニケーションの内容などを記録します。

これは現在処理しているアラートの対応そのものにはあまり影響を及ぼしませんが、対応の取りこぼしがないかをチェックしたり、対応の振り返りや過去の調査をするのに役立ちます。また、アラートの対応にかかる時間や工数を集計することで、アラートの対応にかかるリソースの見積もりや、アラートの対応にかかる費用の見積もりに役立ちます。

アラートの管理は様々な方法がありますが、一つおすすめできるのはチケットシステム（Jiraなど）を利用することです。チケットシステムがセキュリティ監視ではなく開発や運用で使われているのであれば、そこに相乗りするというのも一つの方法です。チケットシステムはアラートの管理に適した機能を持っていることが多く、独自の管理方法を実装するよりも効率的です。

# アラート対応の設計

これらの対応を実業務に取り入れるためには、それぞれの処理をどのように設計するかが重要です。アラート対応の設計におけるポイントをいくつか解説します。

## 🛠️ 通知・周知の範囲と方法

アラートが発生した際に、どのような範囲に通知を行うか、どのような方法で通知を行うかは設計する必要があります。アラートの対応を迅速に始めるために通知は重要な役割を果たしますが、誤検知や関係のない通知の割合が多かったり、そもそも通知の絶対数が多い場合、通知はすぐに**ただのノイズ**になります。そのため、通知の範囲と方法を設計する際には、通知の範囲を限定し、通知の方法を適切に選択する必要があります。

検討要素は以下のような観点があります。

- **通知方法**: 先述した通り、現代においては通知方法が豊富になりましたが、その中からどの方法を選ぶかは重要です。それぞれの通知方法に特性があるのと、組織内でのコミュニケーションのルール・文化に併せて選択する必要があります。
- **通知の範囲**: アラートが発生した際に関係者に通知を行う範囲を指します。通常の関係者はセキュリティ監視を主務としているセキュリティチームや、システム運用を主務としている運用チームなどですが、あまり範囲を広くするとノイズになってしまいます。一方で範囲が狭すぎると気づける人が少なくなり取りこぼしが起きやすくなるという側面もあり、組織内やチーム内で運用のルールと併せて策定する必要があります。
- **アラートの種類に応じた出し分け**: アラートの種類に応じて通知範囲、方法を変えるという手法もあります。この場合は検知しうるアラートを整理して、分類などをする必要があります。重要なポイントとしてここで通知されるアラートというのはまだトリアージされていない＝影響があるかわからない事象、となります。そのためアラートのSeverityが最も高い（例：Critical）からといって広範囲に通知していると、これはただのノイズになってしまいます。トリアージ前とトリアージ後でエスカレーションを分離するというのも検討することができます。
- **アラートの集約**: ノイズ低減の観点では似たようなアラートがでてきた場合にそれを集約して通知を抑制するという方法がありえます。通知系のサービスではこの機能をサポートしているものが多く、有効に活用することで対応者の注意を引く回数を減らし、より重要なアラートに注目しやすくできます。

また、通知の範囲と方法とは少し外れますが、アラートの誤検知や影響のないアラートを件数を減らすようなルールの調整をするサイクルを回す、というのも重要です。これはアラート検知の領分ですが、そもそものアラートの出どころをメンテナンスできないとノイズが増えるだけなので、検知と通知を地続きで考えると良いでしょう。

## 🛠️ トリアージのための情報収集自動化

トリアージは先述した通りアラートの影響度を調査し次のアクションの緊急度を判断する対応ですが、実際の作業としては判断そのものより関連する情報の収集に時間をとられます。そこでアラートが上がってきた時点で自動的に関連情報を収集しておき、人間が影響度などを判定する負荷を減らすというのはよいアプローチです。ただし実施についてはいくつか注意点があります。

- ⚠️ **収集する範囲やアラートの種類を絞る**: 全体のアラート流量にもよりますが、全てのアラートで取得しうる情報を全部取得しようとすると時間がかかりすぎる、外部システムに負荷がかかる、課金などが発生するなどの問題が起きる場合があります。本来アラートの流量は少なくあるべきですが、必要な情報だけを取得するような制御があると良いでしょう。
- ⚠️ **再帰的にデータを取得しない**: アラートに関連するデータを取得するとそこに出現した要素をさらに深堀りする、というのが人間が調査する際のやり方です。しかしこれを自動化しようとするとどこまでを深堀りすればいいかというのを判定するのが難しいため、データ取得処理の負荷が過大になる懸念があります。
- ⚠️ **文脈的な情報を自動収集するのは難しい**: アラートの判定をするうえではログデータなどに現れない文脈が必要な場合も多いです。例えば組織・チームの状況、事業の状況、個人の作業などが挙げられます。これらは自動化するのを諦めて[^llm]人間が収集する前提としても良さそうです。

[^llm]: ただこれについては、生成AIを活用するアプローチはあるのではと考えています。

これらの制約はありますが、適切に運用すれば情報収集自動化は地味に有効なアプローチではあるので、検討をおすすめします。

## 🛠️ アラート管理


- 集計
    - アラート対応に消費している工数
    - アラート対応の時間（初期対応までの遅延や、対応時間）
    - 対応している人の偏り
- 対応手順や確認方法の共有
    - 手順書・ランブックでは対応しにくい暗黙知の部分
    - 新規メンバーも過去に遡りやすい
- 管理方法
    - 既存製品やサービスに付帯している場合は活用する
        - アラートの調査結果を統合できるような仕組み
    - チケット管理システム（例：Jira、GitHub Issue, Projectなど）の活用
        - 統合して利用する必要はあるがシステムの特性が似通っているため相性は良い
        - 組織内で使い慣れているツールを使うと相性が良い

# まとめ