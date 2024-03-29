---
title: "📝 イテレーション"
---

この節では構造データの検査・操作に必要となるRegoのイテレーションの方法について説明します。

Regoは手続き型プログラミング言語ではないため、いわゆる「for文」のようなループの仕組みを持ちません。代わりにいくつかの方法で構造データ（配列型、あるいはキーと値の組み合わせを持つオブジェクト型）の中身を検査したり、構造データから新たな構造データを生成する仕組みを持っています。

便宜上、この記事ではそれらの機能をまとめて「イテレーション」と呼んでいます[^iter]。

# 変数キー

まず代表的な例が、未定義の変数をキーに使うという方法です。

```rego
allow {
    roles := ["developer", "viewer", "admin"]
    roles[x] == "admin"
}
```

未定義の変数を使って配列やオブジェクトを参照すると「条件に一致するすべての値が勝手に代入される」という挙動をします。上記の例では未定義の `x` という変数を使っており、挙動としては `x` が `2` として扱われ、`roles` 末尾の `admin` と一致します。このルールは結果として `true` と判定されます。

```rego
idx = x {
    roles := ["developer", "viewer", "admin"]
    roles[x] == "admin"
}
```

`x` に何が代入されていることを確認するために上記のルールを実行すると結果が `{"idx":2}` となり、`2` が代入されていることがわかります。

「条件に一致するすべての値が勝手に代入される」のを確認するため[^cannot_assign]に、一致する要素を増やしつつ `matched` という集合に値を代入してみます。

```rego
matched[x] {
    roles := ["developer", "viewer", "admin", "admin"]
    roles[x] == "admin"
}
```

結果は `{"matched": [2, 3]}` となり、 `x` へ条件に一致する値がすべて代入されていることが確認できます。

この方法を応用して、あるパスにある値をすべて取得したり、

```rego
# すべてのhostnameが返る
sites[x].servers[y].hostname
```

値の検査をして最低1つ一致するものがあるかを確認できます。

```rego
# hostname が blue のものがあれば1つでもあれば true
sites[x].servers[y].hostname == "blue"
```

# some キーワード

Regoには `some` キーワードがあり、これは参照に使う変数キーを明示的に宣言するために利用します。

```rego
allow {
    some x
    input.roles[x] == "admin"
}
```

冒頭で示した例の通り、仕様上 `some` キーワードなしでも全く同じ動作をしますが、公式では `some` キーワードの利用が推奨されています。これは、未定義の変数のつもりで使っていた変数に値を代入すると、エラーなどにはならないまま意図しない挙動になってしまう恐れがあるためです。Regoはルール内の記述の順序には影響されないため、紛れ込んだ場合に若干見つけづらいということもあるかもしれません。

```rego
allow {
    input.roles[x] == "admin"
    # 〜〜〜〜長いコード〜〜〜〜
    x := 0 # と追記するとエラーにもならず、roles の一番最初の要素しか検査されなくなる
}
```

これを回避するために、 `some` キーワードであらかじめ利用する変数を宣言しておきます。これによって意図せず変数に値を代入するのを防ぐことができます。

```rego
allow {
    some x
    input.roles[x] == "admin"
    x := 0 # ← エラーになる
}
```

# アンダースコア

条件に一致したキーを他の条件式に利用する必要がない、つまりイテレーションによって得られた値だけを検査したり別の変数の生成に利用したい場合、変数キーの代わりにアンダースコア `_` を利用できます。

```rego
allow {
    input.roles[_] == "admin"
}
```

説明の都合上、変数キーを使ったやりかたを先に紹介しましたが、一致するキーを使う必要がなければ積極的にアンダースコアを利用するのがおすすめです。

# 内包表記

Regoではルールや関数によって新たな値を生成することができますが、もう少し簡単に記述できるようにPythonでおなじみの内包表記が使えるようになっています。文法としては `[<結果として返す値> | <ルール>]` となっており、通常のルールと同じく評価結果が真にならない式がある場合は「結果として返す値」も返りません。


```rego
names := [name | sites[i].region == "ap-northeast-1"; name := sites[i].name]
```

内包表記は配列型だけでなく、オブジェクト型を返すこともできます。 `{ <キー>: <値> | <ルール> }` という構文にすると、指定したキーと値で構成されたオブジェクト型の変数が返されます。

```rego
name_map = out {
    # regionが "east" のものだけを抜きだす
    site := [input.sites[x] | input.sites[x].region == "east"]

    # nameをキーに、hostnameを値にして新しいオブジェクト型を作り、name_map に代入する
    out := { s.name: s.hostname | s := site[_].servers[_] }
}
```

# 参考文献

- Some keyword: https://www.openpolicyagent.org/docs/latest/policy-language/#some-keyword
- Membership and iteration `in`: https://www.openpolicyagent.org/docs/latest/policy-language/#membership-and-iteration-in

[^iter]: ~~公式ドキュメントでは、これらの機能の総称は特にないようです~~ (2021.12.21訂正) 公式でもiterationと呼ばれていました https://www.openpolicyagent.org/docs/latest/policy-reference/#iteration
[^cannot_assign]: ちなみに `idx = x {...}` のルールで複数の異なる値を返そうとすると、同じ変数に複数回代入を試みたとみなされて失敗します