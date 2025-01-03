---
title: "📐 アラート対応の設計"
---

本書ではアラート対応の自動化、エンジニアリングまでを取り上げますが、まずはアラート対応とはどういうものか、どう設計するべきかという観点について議論します。

# 「アラート対応」の位置づけ

まず、本書における「アラート対応」の位置づけを整理します。情報セキュリティにおいて問題を検知した後の対応としては「インシデントレスポンス」が有名です。しかし、インシデントレスポンスという言葉は非常に広い意味を持っており、例えば[NISTのSP 800-61 Computer Security Incident Handling Guide](https://csrc.nist.gov/pubs/sp/800/61/r2/final)では、セキュリティ監視全般がインシデントレスポンスの一部として扱われています。そこで本書では「インシデントレスポンス」という言葉を使わずに「アラート対応」という言葉を使用しています。

今回の解説では、「アラート対応」と「インシデント対応」を区別しています。「アラート対応」は、アラートが報告されたときにそれが組織に影響を及ぼすかどうかを判断する過程を指します。一方、「インシデント対応」は、アラートが組織に影響を及ぼすと判断された場合に、その影響を最小限に抑えるための対応を指します。実務においてはこの2つの過程は連続しており、明確に境目を区切ることは難しいですが、それぞれの過程において求められる役割は明確に異なります。

本書では「インシデント対応」には触れませんが、「アラート対応」について、その設計や自動化について解説します。

# アラート対応の種類

具体的にアラート対応で行うべき処理について整理します。

## 📋 通知・周知

まずはアラートが発生した際に、関係者に通知を行う処理です。アラートを検知してもそのまま放置していては意味がないため、迅速に関係者に通知することが重要です。

現代において通知の方法は様々です。少し前まではメールと電話＋SMSが主流でしたが、最近ではSlackなどのチャットツールがビジネスコミュニケーションでも活用されており、それを利用することも可能です。また、PagerDutyやOpsGenieなどのアラート管理サービスを利用することもあります。特にアラート管理サービスでは条件に応じて通知方法や通知先を選ぶことができるため、柔軟な通知設定が可能です。

## 📋 トリアージ

アラートが発生した際に、そのアラートが組織に影響を及ぼすかどうかを判断する処理です。アラートが発生したからといって、それが組織に影響を及ぼすかどうかは必ずしも明確ではありません。誤検知や影響のない攻撃もあります。そのため、アラートが発生した際には、そのアラートが組織にどのような影響を及ぼすかを判断する必要があります。トリアージでは影響の有無だけでなく、影響度の高さや対応の優先度も判断することが求められます。

トリアージは報告されたアラートに含まれる情報だけでなく、関連する情報の収集が必要となる場合が多いです。関連する情報は以下のようなものがあります。

- 📌 **アラートに登場した要素に関するログ**: 主体（例：IPアドレス、ユーザ名、ファイル名など）やリソース（例：ファイル、データベース、サーバなど）に関するログデータを、データウェアハウスから取り出します。
- 📌 **アラートに登場した要素に関する外部情報**: 主に主体について、レピュテーション情報やIoC（Indicator of Compromise）として記録されていないかを確認します。
- 📌 **アラートの要素の現状調査**: 主にリソースについて、現在の状況を直接的・間接的に確認します。例えばインスタンスだった場合、プロセス・ファイルシステム・ネットワークの状況などを確認します。特殊なツールを用いる場合もあります。
- 📌 **関係者への確認**: 主体が内部のユーザだった場合、その挙動が意図的だったのかや、何か関連した作業をしていたのかなどを確認します。

これらの情報を必要に応じて収集しながら、アラートの影響度を判断することが求められます。

## 📋 暫定処置

アラートがまだ組織に影響を及ぼすかどうかを判断する前の状況であっても、その影響が大きい可能性がある場合には暫定処置を行うことがあります。例えばインスタンスや端末への侵入が疑われる場合に、一時的にそのインスタンスや端末へのアクセスを遮断したり、その時点でのバックアップを作成してデータの保全や証拠の確保を行うことが考えられます。

この対応は投機的であり、実際には影響を及ぼさない可能性も考慮しなければなりません。そのため、バックアップ作成などの非破壊的対応は比較的安全ですが、アクセスを遮断するなどの破壊的対応は慎重に行う必要があります。特に実運用環境での対応は、アクセスの遮断が同系列のシステム、あるいは他のサービスに影響を及ぼす可能性があり、より慎重さが求められます。

## 📋 アラート管理

アラートが発生した際に、そのアラートに関する情報を記録する処理です。そのアラートが今どういうステータス（未着手、調査中、調査終了：影響なし、調査終了：影響あり、など）なのかだけでなく、トリアージや暫定処置をするにあたっての経過の情報や、ステークホルダーとのコミュニケーションの内容などを記録します。

これは現在処理しているアラートの対応そのものにはあまり影響を及ぼしませんが、その後にいくつかの点で役に立ちます。

- 👍️ **対応の取りこぼしを防げる**: 通知だけだとどのアラートの対応が完了したのかの見通しが悪く、対応の取りこぼしが起こりやすいです。これを防ぐためにアラートごとの状態の管理をするのが有効です。
- 👍️ **文脈や暗黙知の共有に役立つ**: アラートを対応した過程を記録しておくことで、何を調査しどのような基準で判断したのかを別のメンバーと共有できます。特に新しく参加したメンバーがキャッチアップするのにも役立ちます。
- 👍️ **対応に関する偏りを調査できる**: アラートをチームで対応する場合など、対応した人物の偏りや時間帯の偏りなどをあとから分析することができます。
- 👍️ **対応にかかる時間や工数の集計や見積もりに使える**: 対応開始から完了までの時間などをみることで、全体的に対応にかかる時間や工数を把握し、今後の計画などに役立てることができます。

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
- ⚠️ **文脈的な情報を自動収集するのは難しい**: アラートの判定をするうえではログデータなどに現れない文脈が必要な場合も多いです。例えば組織・チームの状況、事業の状況、個人の作業などが挙げられます。これらは自動化するのを諦めて人間が収集する前提としても良さそうです。

これらの制約はありますが、適切に運用すれば情報収集自動化は地味に有効なアプローチではあるので、検討をおすすめします。

# まとめ

今回はアラート対応における通知・周知、トリアージ、暫定処置、アラート管理の役割と、それらの要点について説明しました。次回はこれらを自動化するにあたっての実装の要点について解説します。
