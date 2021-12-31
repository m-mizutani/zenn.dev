---
title: "📕 はじめに"
---

この本では、最近セキュリティエンジニア界隈で注目されつつある汎用的なポリシーエンジン[OPA](https://www.openpolicyagent.org/docs/latest/)（読み：オーパ）と、OPAで利用するポリシー記述言語[Rego](https://www.openpolicyagent.org/docs/latest/policy-language/)（読み：レゴ）について解説していきます。

この本では既存のツールにとらわれず、OPA / Regoの基礎的な部分と活用について解説します。OPAやRegoは[Gatekeeper](https://github.com/open-policy-agent/gatekeeper)や[Conftest](https://www.conftest.dev/)の文脈で語られることが多く、Kubernetesやterraformのためのツールであると考えている方もいらっしゃるかもしれません。実際にはRegoは特定のツールに依存しない汎用的なポリシーをコードとして記述でき、OPAは様々なシステムと連携できるポリシーエンジンです。そのため、本書では既存のツールに関する解説は取り扱わず、より基本的な部分を取り扱うことにしました。

本書を読み始めるにあたって以下を参考にしてもらえればと思います。

- そもそもOPAでどんなことができそうか？ というイメージがつかない方は[OPA/Regoとはなんなのか](./intro-overview)から御覧ください
- なぜポリシーをコード化する必要があるのか？と思われている方は[Policy as Code](./policy-as-code)をどうぞ
- Regoによるポリシーの記述方法をゼロから習得したい場合は[第1章 Regoの基礎](./chap-rego)がオススメです
- Regoは習得済みだけどOPAをどのように連携・活用できるか知りたい、という場合は[第2章：OPAの実践的な利用](./chap-opa)へお進みください
