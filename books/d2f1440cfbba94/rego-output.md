---
title: "📝 結果の出力"
---

この節ではOPAで利用されるポリシー記述言語であるRegoで出力される変数への代入のパターンを解説します。

Regoはポリシーのトップレベルで定義された変数がそのまま「出力」として扱われますが、代入にはいくつか方法があります。特に条件の分岐や値の入れ込み方などがやや特殊なため、パターンごとに具体例で解説していきたいと思います。

# 代入のパターン

## 直代入

```rego
role = "admin"
```

まずはもっともシンプルなパターンとして、イコールを使って決まった値を代入できます。あるいは関数を作ることができるので、関数からの返り値を代入させることもできます。

## if

```rego
allow {
	input.user == "blue"
}
```

`変数名 { ルール }` という形式で書くとルール内の評価式が成立する場合に `true` が変数に代入されます。気をつけなければならないこととして、評価式が成立しない場合は **変数に何も代入されません**。上記の例で`input.user` が`blue`以外だと `allow` という変数自体が出力に存在しません。

ルールが成立しない場合になにか値を入れいたい、という場合は `default` キーワードを使います。

```rego
default allow = false

allow {
	input.user == "blue"
}
```

これによって `input.user` が `blue` ではなかった場合、`{"allow":false}` が返されます。

## if-then

```rego
role = "admin" {
	input.user == "blue"
}
```

`変数名 = 値 { ルール }` という記述によって、ルールが成立した場合に任意の値を代入できます。

先述したとおり、ルール内の複数条件は論理積（AND条件）として扱われるため、論理和（OR条件）は以下のように扱います。

```rego
role = "admin" {
	input.user == "blue"
}
role = "admin" {
	input.user == "orange"
}
```

これで `input.user` が `blue` もしくは `orange` のときに `{"role":"admin"}` が返ります。同じような方法で、入力値に応じて出力値を選択する、ということも以下のようにできます。

```rego
role = "admin" {
	input.user == "blue"
}
role = "reader" {
	input.user == "orange"
}
```

## if-else-then

条件が複数あって入力値から必ず一意に値が決まる場合は良いのですが、複数の値を代入しようとするとエラーになります。

```rego
role = "admin" {
	input.user == "blue"
}
role = "reader" {
	input.team == "developer"
}
```

上記のポリシーに対し、`{"user":"blue", "team":"developer"}` という入力を渡すと下記のようなエラーになります。

```
policy.rego:3: eval_conflict_error: complete rules must not produce multiple outputs
```

この場合はどちらの判断が優先されるかを明示するため、 `else` キーワードを使います。

```rego
role = "admin" {
	input.user == "blue"
} else = "reader" {
	input.team == "developer"
}
```

これで `input.user == "blue"` が成立しないときだけ、`input.team == "developer"` が評価され、成立すると `reader` が渡されます。

## ルール内の変数を利用して代入する

ルール内は1つのスコープとして扱われ、ルール内で定義された変数はそのルール内でのみ有効です。ただしこのスコープはカッコ内 `{...}` だけでなく、変数に代入する部分もスコープ内として扱われます。そのため、ルール内で生成・加工されたデータを出力に利用できます。

```rego
denied_msg = msg {
    input.user != "alice"
    msg := sprintf("%s is not allowed", [input.user])
}
```

上記ルールは `user` が `alice` ではなかった場合に、 `denied_msg` にメッセージを代入します。

このようにルール内の変数をそのまま入力するだけでなく、変数側に利用することもできます。

```rego
filtering[req.dst] = "allowed" {
    req := input.requests[_]
    req.src == "blue"
}
```

`_` については後ほど説明しますがイテレーションを意味します。上記のようなポリシーだと `filtering` がオブジェクト型（キーと値を持つ辞書型）になり、`src` が `blue` のエントリーがあれば `dst` をキーとして `allowed` を代入します。

```json
{
	"requests": [
        {"src": "orange", "dst": "10.0.0.1"},
        {"src": "blue", "dst": "10.0.0.2"},
        {"src": "red", "dst": "10.0.0.3"}
    ]
}
```

上記のようなデータを入力すると、下記のようになります。

```
{
    "filtering": {
        "10.0.0.2": "allowed"
    }
}
```

またRegoの特殊な記法として、`変数名[キー名] { ルール }` という記述をすると、ルールが真になるときにキー名の集合が作成されます。

```rego
filtering[req.dst] {
    req := input.requests[_]
    req.src != "blue"
}
```

と変えることで

```json
{
    "filtering": [
        "10.0.0.1",
        "10.0.0.3"
    ]
}
```

というような出力結果になります。

この方法は実際のルールでも多く利用されており、「ポリシーによって拒否された理由が記載された文字列を `deny_msg` のような変数に集合の要素として追加していくことで、任意の数の拒否理由を一度に連携しているツールやシステムに伝えることができます。

```rego
deny_msg[msg] {
    input.request.user != "blue"
    msg := "User is not blue"
}

deny_msg[msg] {
    input.request.path != "/api/test"
    msg := sprintf("Requested path %s is not allowed", [input.request.path])
}
```

上記ポリシーから以下のような出力が生成されます。

```json
{
    "deny_msg": [
        "Requested path /some/where is not allowed",
        "User is not blue"
    ]
}
```

# まとめ

OPAは結果の生成方法もややクセがありますが、条件判定の方法、ルールと変数のスコープ、集合の扱い方をおさえればあとは組み合わせで概ねのユースケースは網羅できるかと思います。組み合わせによる応用の範囲は広いので、いろいろな場面に活用できればと思います。