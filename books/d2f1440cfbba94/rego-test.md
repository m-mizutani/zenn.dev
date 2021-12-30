---
title: "テスト"
---

[Policy as Codeとは]()の章でも述べたとおり、ポリシーをコードで記述する大きなメリットの1つがテスト可能になることです。シンプルで少ないポリシーだけを運用しているうちはいいですが、ポリシーが複雑化・巨大化することによって記述した内容が意図したとおりに動作するか、あるいは新たに追加・修正したことで既存のポリシーに影響を及ぼしていないかを確認するコストが肥大化していきます。

OPAは[ポリシーをテストする機能](https://www.openpolicyagent.org/docs/latest/policy-testing/)を提供しており、容易にテストの記述や実施ができるようになっています。この記事ではテスト機能の基本的な部分をかいつまんで紹介します。

# 基本的なテストの流れ

以下のようなポリシーがあった場合のテストについて説明します。

```rego:policy.rego
package testing

admins := ["alice", "bob"]

allow {
    input.user == admins[_]
}
```

## テスト用ファイルの作成

`policy_test.rego` という名前で以下のようなファイルを作成します。

```rego:policy_test.rego
package testing

test_allow {
    allow with input as {"user": "alice"}
}
```

`opa test` コマンドは指定したディレクトリから再帰的に `*.rego` ファイルを読み込み、`test_` prefixを持つルールをテストします。 `test_` prefix を持つルールはどのファイルに配置されていてもよく、テスト対象が記述されているファイル（今回の例では `policy.rego` ）内に配置することもできます。ただし、ポリシーをデプロイする際に本体のルールとテストを分離するために、テスト用のファイルを分離しておくのが良さそうです。

[Go言語のように](https://go.dev/doc/tutorial/add-a-test)ファイル名によって呼び出しなどの挙動が変わるわけではありませんが、`_test.rego` というsuffixを持つファイルにするのが通例のようです。

例の `policy_test.rego` では `test_allow` がテストとして呼び出されます。動作は通常のルールと同じで、カッコ `{...}` 内の式の評価がすべて真になればテストが成功、1つでも偽があれば失敗の扱いになります。

## テストの実行

`opa test` コマンドで実行できます。引数で指定したディレクトリを再帰的に探索して `*.rego` ファイルを読み込みます。

```sh
$ opa test -v .
data.testing.test_allow: PASS (292.666µs)
--------------------------------------------------------------------------------
PASS: 1/1
```

# データのmocking

テストでは入力するデータを変更することで、条件が意図した通りに機能しているかをチェックします。Regoではデータをmockして自由にテストができるようになっています。

## 入力値のmock

先程の例では `input.user` が `admins` 内にある値だった場合に `allow` が真になる、というルールでした。ここで `input` の値を `with` キーワードを使うことで上書きし、意図したとおりに許可・拒否ができているかを確認できます。 `with` キーワードで上書きする変数を指定し、 `as` でmockさせるデータを指定します。

```rego
test_allow {
    allow with input as {"user": "alice"}
}

test_disallow {
    not allow with input as {"user": "chris"}
}
```

## ポリシーにでてくる変数の上書き

`input` と同様に変数を上書きすることもできます。

```rego
test_disallow_with_other_admins {
    not allow with input as {"user": "alice"} with admins as ["blue"]
}
```

`with` キーワードは複数記述することで、複数の変数をテスト中に上書きできます。上記の例では

```rego
admins := ["alice", "bob"]
```

となっていた変数を

```rego
admins := ["blue"]
```

と書き換えることによって、入力データが `{"user":"alice"}` でも `allow` が偽になっています。

## データファイルを使った変数の上書き

JSONなどのファイルをdataとして利用してmockすることもできます。

```json:testdata/admins.json
{
  "admins": ["blue"]
}
```

```rego
test_with_data_admins {
    allow with input as {"user": "blue"} with admins as data.testdata.admins
    not allow with input as {"user": "alice"} with admins as data.testdata.admins
}
```

テストに利用するデータが大きい場合、ファイルを分離することで可読性が上がります。ただし注意点として `data.testdata.admins` のパスは相対ファイルパスに依存するため、テストを実行するディレクトリを固定する必要があります。

## 構造データの部分的な値の書き換え

フィールド数が多い、あるいは構造が複雑なデータが必要なテストの場合、テストの種類（例えば同じルールに対する成功ケースや失敗ケース）ごとにわずかに違うデータを持つのはメンテナンス性が悪くなってしまいます。そこで `object.union` を使うことで部分的にテスト用の構造データを書き換えることで、わずかに違うデータを複数持たずによくなります。

先程のルールを少し拡張し、`request` というネストされた構造データをチェックするようにしました。

```rego
allow_action {
    input.user == admins[_]
    input.request.target == "db"
    input.request.action == "read"
}
```

これに対して `object.union` を使うことで指定したフィールド（今回は `request.action` ）のみを書き換え、失敗するケースのためのデータを生成しています。

```rego
test_modify_input {
    success_case := {
        "user": "alice",
        "request": {
            "target": "db",
            "action": "read",
        },
    }

    fail_case := object.union(success_case, {"request": {"action": "write"}})

    allow_action with input as success_case
    not allow_action with input as fail_case
}
```
