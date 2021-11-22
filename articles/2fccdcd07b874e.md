---
title: "Regoの基礎（パッケージ編）"
emoji: "👋"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["OPA", "Rego"]
published: false
---

この記事は[OPA/Regoアドベントカレンダー](https://adventar.org/calendars/6601)のN日目です。

Regoにはコードを分割して管理するための仕組みとして「パッケージ」という概念を持ちます。パッケージは名前空間を分けるために利用されます。

```rego
package test

allow = {
    input.hoge
}
```

![](https://storage.googleapis.com/zenn-user-upload/911df1587e94-20211120.jpg)

[ドキュメント](https://www.openpolicyagent.org/docs/latest/policy-language/#imports)によるとパッケージの依存関係を宣言するために `import` を利用するとありますが、現在の実装(ver 0.34.2)だと `import` をしなくてもOPAが読み込み済みのパッケージは `data.<package名>` によってアクセス可能です。[issueのコメント](https://github.com/open-policy-agent/opa/issues/491#issuecomment-338704022)を見ると現在 `import` はパッケージのAliasを作成するために利用されているようです。
