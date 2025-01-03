---
title: "🛠️ 生成AIの活用"
---

本書を執筆している2024年末時点でも、生成AI（Generative AI）はさまざまな分野で利用されています。生成AIは、画像や音声、テキストなどのデータを生成するAI技術で、特に自然言語処理の分野で大きな進歩を遂げました。例えば、文章の要約や翻訳、質問応答、文章生成などのタスクにおいて、生成AIは人間に匹敵する精度を持つようになりました。

# 生成AIがセキュリティ監視でできなさそうなこと

まず、セキュリティ監視において生成AIが **できなさそうなこと** について考えてみます。生成AIが人間に匹敵する精度を持つようになったことで、さまざまな期待が膨らみますが、現状の技術の延長線上で考えると、あまり現実的ではないことを挙げてみます。もちろん、今後の技術発展やブレイクスルーによって可能になることもあるかもしれませんし、既存の技術でも工夫次第で実現できることもあるかもしれません。

## ❌️ ログデータを分析しての異常検知

本書ではあまり触れていませんでしたが、アラート検知の方法として、ログデータを検索・集計するだけでなく、セキュリティアナリストが直接ログデータを検索・分析して異常を検知する「Threat Hunting」という手法があります。これを組織内で実施するためには、専門的な知識を持った専任のメンバーが必要となる場合がほとんどで、その体制を整えることが難しい組織が多いです。この役割を生成AIに担わせたいという期待はあると思います。

これを実現するにあたっての困難なポイントの一つは、監視や監視対象に関する環境、文脈の情報をどのように与えるかです。システム構成やネットワーク構成の情報だけでなく、どのようなシステムを持つのか、どのような組織なのか、どのような業務をしているのかなどの情報も重要です。これらの情報は大量かつ暗黙のうちに扱われていることが多く、適切に生成AIに入力するのが難しいと考えられます。

もう一つの課題は、ログデータをどのように与えるかです。現状の生成AIの技術では、入力するデータサイズによって課金されます。ログデータは非常に大量であり、それを直接生成AIに与えることはコストがかかりすぎる可能性があります。ログの一部を切り出すとしても、切り出し方によって検知の性能が大きく変わる可能性があり、適切なデータを選択することが難しいと考えられます。

以上の理由から、Threat Huntingの代替を生成AIに求めることは、当分の間は難しいと考えられます。

## ❌️ アラートの深刻度判定

アラート対応の中には、トリアージというアラートの深刻度を判定する作業があります。アラートの深刻度を判定するためには、アラートに関連する情報を収集し、その情報をもとに判断する必要があります。アラートの深刻度はアラートの内容だけでなく、組織の状況や環境、事業の内容が大きく影響します。例えば、特定のサーバに対する攻撃であれば、そのサーバが重要かどうか、そのサーバにどのようなデータが保存されているか、そのサーバがどのようなネットワークに接続されているか、そのサーバで動いているOS、ミドルウェア、アプリケーションは何か、どのような脆弱性があるのかなどが重要な要素となります。

Threat Huntingの話と同様に、組織や環境に関する情報を適切に生成AIに入力することは難しいですし、生成AIによる出力には責任を持たせることができません。最終的な判断は結局のところ人間が実施する必要があります。情報収集のサポートという側面はありますが、アラート対応の節で述べたように、関連データを取得するのであればルールを定めてそれに則って取得する方が再現性もあり、使いやすいでしょう。したがって、アラートの深刻度判定に生成AIを介入させるメリットは現状ではあまり見込めないと考えられます。

## ❌️ インシデントの調査や対応

これも同様に、組織に関する情報を適切に生成AIに入力することが難しいと考えられます。インシデントの調査や対応には、前述した2つ以上に組織の状況や構成、環境、事業内容が大きく影響します。また、インシデント対応では、法的な観点や証拠保全の観点も重要です。生成AIがこれらの観点を適切に考慮して調査や対応を行うことは難しいと考えられます。

# セキュリティ監視と生成AIでできそうなこと

では逆に、生成AIがセキュリティ監視で **できそうなこと** について考えてみます。異常検知や深刻度判定という重大なタスクは難しいと考えられますが、生成AIがセキュリティ監視のオペレーションにおける補助的な役割を担うことは可能性があると考えられます。

## ✅️ 大量のログデータやアラートの要約や調査

アラート対応時に登場した主体（IPアドレス、ユーザ名、ファイル名など）やリソース（ファイル、データベース、サーバなど）に関するログデータを取得して、それをもとにトリアージすることがあります。この場合、調査する時間帯を絞るなどすることで対象となるログデータは数十から数千程度となることが多いですが、それらを1行ずつ理解して読み全体を把握するのはなかなか時間がかかる作業です。

この場合、生成AIにそのログデータをそのまま投入して質問ベースでログの内容を把握するということが考えられます。例えば以下のような質問が考えられます。

- 💬 「ログの内容から何が起こったのかを要約して」
- 💬 「このIPアドレスが何をしているのかを調べて」
- 💬 「このログに出現したIPアドレス/ユーザ/リソースを一覧にまとめて」
- 💬 （似たようなログが多い状況で）「特徴のあるログを抽出して」

このような質問に対して生成AIが適切な回答を返すことで、ログデータの要約や調査を効率化することができると期待できます。

また、ログと同様にアラートも要約や調査が可能です。アラートも検知側の問題で似たようなアラートが大量に発生することがあります。これを1つずつ調査するのは非常に時間がかかる作業ですが、似たようなアラートを分類しつつ仕分けした上で対応すれば、対応にかかる時間の削減が見込めます。

## ✅️ ルール更新の補助

セキュリティ監視では、アラートの検知ルールを定期的に更新することが必要です。これは新しい攻撃手法の出現、新しい脆弱性の発見、誤検知の低減、監視対象の環境の変化への対応など、さまざまな理由によるものですが、特に誤検知の低減は日々の運用において重要です。

セキュリティ監視のエンジニアリングの観点から、テキストベースのルール履歴管理とテスト可能性などを考慮すると、Gitなどのバージョン管理システムとCI/CDパイプラインを利用するのが安全なデプロイのために良い方法です。しかし、その分ルール変更の手間もややかかります。具体的に誤検知低減のためのルール更新をしようとすると以下のような手順が必要です。

1. 誤検知の元になったデータを取得
2. データを見ながら誤検知の特徴となったパターンを抽出
3. 現状のルール記述の平仄をあわせながら誤検知の特徴を含むルールを追加・修正
4. テストデータを用意
5. テストデータに基づいたテストを記述
6. テストを実行して問題ないことを確認
7. バージョン管理システムへコミットし、CI/CDパイプラインを通してデプロイ

これらの作業はスムーズに行けば10分程度ですが、場合によっては20〜30分ほどかかることもあります。セキュリティ監視を専任で行うチームの場合は良いですが、運用チームや開発チームが兼任で行っている場合は、この作業を行う時間がなかなか取れなかったり、億劫に感じて後回しになりがちなこともあります。

生成AIがこの作業を補助することができれば、ルール更新の作業を短縮することが期待できます。手順1は自動的に行う（例えばDBなどに保存されたものを取得できるようにするなど）機能を実装すれば良いでしょう。元になったデータと既存のルールを入力とし、「このデータの検知を無視するようなルールを追加して。さらにテストデータを生成し、テストも追加して」というような質問を生成AIに投げることで、手順2〜5を効率化することができます。最後に人間がテスト内容とテスト結果を確認し、CI/CDパイプラインを通してデプロイするという流れになります。

これによって全体の7〜8割程度の作業を生成AIが補助することができると考えられます。単純に時間を短縮するだけでなく、作業に対する心理的障壁を下げることができるため、ルール更新の頻度を上げることができると期待できます。

アラート対応の実装でも紹介したAlertChainでも実験的にこの機能を取り入れています。

https://github.com/secmon-lab/alertchain/pull/98

```shell
% export ALERTCHAIN_GEMINI_PROJECT_ID=your-project
% export ALERTCHAIN_GEMINI_LOCATION=us-central1
% export ALERTCHAIN_DB_TYPE=firestore
% export ALERTCHAIN_FIRESTORE_PROJECT_ID=your-project
% export ALERTCHAIN_FIRESTORE_DATABASE_ID=alertchain
% alertchain new ignore \
    -i 30a7bdd6-7d55-419a-9a1d-220c406946d1 \ # alert ID
    -b policy/alert/scc.rego \                # ベースとなるポリシー
    -d policy/alert/test/scc \                # テストデータを設置するディレクトリ
    -r data.alert.test.scc                    # テストデータのパス
```

このようなコマンドを実行することで、AlertChainが誤検知したアラートのデータを取得し、それをもとに生成AI（ここではGoogle CloudのGemini APIを利用）を用いてアラートの無視ルールを生成することができます。

![](https://storage.googleapis.com/zenn-user-upload/50a6dcaa7496-20241225.png)

実際に生成されたルールが上記のようになり、特定のアラートを無視するルールが生成され、テストデータも生成されます。ただしまだ実験的な試みであり、必ず期待したルールが生成されるわけではないので、あくまでルールの原型を生成するための補助として利用するのが良いかもしれません。

## ✅️ アラート内容についての問い合わせ

発生したアラートが組織内部のメンバーの作業によるものであった場合、そのメンバーが意図的に実施したのであれば問題なしとできるようなアラートもあります。例えば、ベストプラクティスに沿わないようなミスコンフィギュレーションの警告や、クラウドリソースの不審な操作などです。これらは本来起こるべきではありませんが、業務遂行上やむを得ずそのような処置をしているというケースも実務上は多々起こり得ます（もちろんうっかり、というケースもありますが）。

このような場合、そのアラートの内容を本人に問い合わせて、それが意図したものかどうかを確認することがあります。その場合、例えばアラートを管理するチケットをそのまま渡してその当人に移譲できるかというと、現実には難しいと考えられます。理由としては **アラートの内容がわかりにくい** というのが挙げられるでしょう。アラートは対応をするアナリストや担当者が分析などをしやすいように、なるべく多くの情報を含めるように設計されることが多いです。そのため、普段からそのアラートに慣れている、あるいはそのアラートに関する専門的な知識がある人でないと、アラートの内容を理解するのは難しいことがあります。

これを解消するために、生成AIがアラートの内容を要約し、なぜ問い合わせているのかを含めた質問を生成することができれば、本人への質問を効率化することができます。問い合わせの過程で途中からセキュリティ監視側の担当者が入っても良いですし、生成AIでのやりとりで完結した内容をあとから担当者が確認する、というアプローチも考えられます。ただし、アラートの内容が脆弱性を生み出す、あるいは機密情報を漏洩するようなものであれば、当人のアカウントが乗っ取られている可能性もあるため、最終的な判断は人間に委ねるのが望ましいでしょう。

# まとめ

実装の章の締めくくりとして、生成AIがセキュリティ監視においてどのような役割を担うことができるかについて考えてみました。生成AIは現状、人間の専門家を超える働きは難しいと感じますが、セキュリティ監視のオペレーションにおける補助的な役割を担うことで、全体的な業務効率化を実現する可能性を感じています。

今後の生成AIの発展により、セキュリティ監視や監視基盤の運用においてどのような変化が起こるのか、非常に楽しみです。利用できる道具をうまく活用し、エンジニアリング的な工夫も取り入れつつ、セキュリティ監視が今後より取り組みやすいものになっていくことを期待しています。
