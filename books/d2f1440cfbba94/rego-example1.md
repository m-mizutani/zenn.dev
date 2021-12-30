---
title: "記述例1 (OPAサーバの認可とテスト)"
---

この章では具体的なユースケースに基づいてRegoの記述例を紹介したいと思います。公式でも既存のインテグレーション事例がいくつか紹介されており、[Kubernetes を題材に使用例](https://www.openpolicyagent.org/docs/latest/kubernetes-primer/)も解説されています。

# APIサーバへのアクセスを制限するポリシー

`opa` コマンドはCLIでポリシーを評価するだけでなく、[サーバの機能](https://zenn.dev/mizutani/articles/f00d3ca12e4102)も提供されています。そのサーバに対するアクセス制御もRegoで記述できるようになっています。詳しい仕様については[公式ドキュメント](https://www.openpolicyagent.org/docs/latest/security/#authentication-and-authorization)に解説を譲り、今回は具体的な記述について説明していきたいと思います。

今回用意したポリシーは以下で、目的は「`/v1/data/*` に対して `GET` と `POST` のアクセスだけを許可する」になります。

```rego
package system.authz

default allow = false

allow {
    allowed_method
    allowed_path
}

# Check method
allowed_method {
    input.method == "GET"
}
allowed_method {
    input.method == "POST"
}

# Check path
allowed_path {
    print(input.path)
    input.path[0] == "v1"
    input.path[1] == "data"
}
```

それでは、上から順番に解説していきます。

```rego
package system.authz
```
まずはパッケージ名の宣言です。基本的にパッケージ名は利用者側で自由に利用できますが、`system` はOPA自身によって予約されています。（他にも `data` や `input` が予約語としてあり、勝手に利用できない）管理運用の面から考えても、評価したい対象をパッケージ名で表現・区別するというやりかたは比較的メジャーなやりかたと思われます。

`opa` コマンドは `--authorization=basic` というオプションが与えられた際、 `system.authz` パッケージをクエリして `allow` が真だった場合はアクセスを許可、偽だった場合に拒否するという動作をします。

```rego
default allow = false
```
今回は `allow` のデフォルトを `false` にして、条件に一致しないものはすべて偽 → アクセス拒否となるようにしました。

```rego
allow {
    allowed_method
    allowed_path
}
```

そしてこれが判定に用いられる `allow` 変数になります。この書き方は特定の値を代入していないため、`{ ... }` 内の式がすべて真だった場合（積条件）には `allow` に `true` が代入されます。

```rego
allowed_method {
    input.method == "GET"
}
allowed_method {
    input.method == "POST"
}
```

`allowed_method` はその名の通り許可されているメソッドかどうかをチェックします。見てわかるかと思いますが、`system.authz` パッケージでリクエストの認可判定をするために、 `input` にリクエストの内容が詰め込まれて渡されます。どのような値が入るかは公式ドキュメントを参照していただきたいですが、基本的にHTTPリクエストに出現する情報は一通り引き渡されます。また今回は扱いませんが[jwtの検証をする組み込み関数](https://www.openpolicyagent.org/docs/latest/policy-reference/#token-verification)も用意されていたりするので、認証もやろうと思えば実装できます。

さて今回は先述したとおり `GET` もしくは `POST` のどちらかであれば許可するとしています。先程の `allow { ... }` のような書き方だと論理積扱いになってしまうため、このように2つに分けて記述しています。これは厳密にはOR条件ではなく、両方の `allowed_method` が評価されて結果が代入されます。ただし、内部の条件が偽の場合は「`false` を代入しようとする」のではなく「何もしない」になります。さらにOPAは二重に「別の値」を代入しようとするとエラーになりますが、同じ値が何度も代入される分にはエラーになりません。これらの特性から、このルールは二重代入とは扱われずに実質OR条件のように振る舞います。

```rego
allowed_path {
    input.path[0] == "v1"
    input.path[1] == "data"
}
```

最後はパスの確認です。パスは`input.path`に `/` で分割されて格納されています。例えば `/v1/data/foo/bar` にアクセスした場合は `["v1", "data", "foo", "bar"] = input.path` となります。今回はシンプルにprefixが `/v1/data` であることを確認したいため、

# system.authz のテスト

ポリシーの記述例を紹介したので、併せてテストの実例も紹介したいと思います。

## 基本のテスト

まずはシンプルに1つずつ記述したテストになります。[テストの解説](https://zenn.dev/mizutani/articles/85c9992f601068)でふれたとおり、`with` と `as` キーワードを使用することで `input` の値を上書きし、`method` や `path` に任意の値を入れてテストしています。

```rego:authz_test.rego
package system.authz

test_allow_get {
	allow with input as {
		"path": ["v1", "data", "foo"],
		"method": "GET",
	}
}

test_allow_post {
	allow with input as {
		"path": ["v1", "data", "foo"],
		"method": "POST",
	}
}
```

上記例は成功ケースで、失敗ケースも記述できます。以下の例では禁止されている `DELETE` メソッドや `/v1/data` 以外のパスにアクセスした場合に拒否されていることを確認しています。

```rego
test_disallow_method {
	not allow with input as {
		"path": ["v1", "data", "foo"],
		"method": "DELETE",
	}
}

test_disallow_path {
	not allow with input as {
		"path": ["v1", "policy"],
		"method": "GET",
	}
}
```

## Table driven test

ここまでの例のように愚直に `with` キーワードで値を書き換えていくという書き方ももちろんできるのですが、テストの量が多くなってくると全体の見通しが悪くなったり、どのテストが失敗しているのかが若干わかりにくくなる[^trace]という問題があります。この課題を解決するために、Go言語などでよく見られるTable driven testで記述するというアプローチがあります。[こちらのブログ](https://techblog.szksh.cloud/opa-table-driven-test/)で事例として紹介されていたので、少しアレンジしたものを今回のケースに合わせて紹介します。

```rego
test_authz {
	count(authz_failed_results) == 0
}

authz_failed_results[failed] {
	tests := [
		{
			"title": "GET method is allowed",
			"input": {
				"path": ["v1", "data", "foo"],
				"method": "GET",
			},
			"exp": true,
		},
		{
			"title": "POST method is allowed",
			"input": {
				"path": ["v1", "data", "foo"],
				"method": "POST",
			},
			"exp": true,
		},
		{
			"title": "DELETE method is not allowed",
			"input": {
				"path": ["v1", "data", "foo"],
				"method": "DELETE",
			},
			"exp": false,
		},
		{
			"title": "other than /v1/data is not allowed",
			"input": {
				"path": ["v1", "policy"],
				"method": "GET",
			},
			"exp": false,
		},
	]

	t := tests[_]
	result := allow with input as t.input
	t.exp != result
	failed := sprintf("failed test '%s'. expected %v, but got %v", [t.title, t.exp, result])
	print(failed)
}
```

流れを説明すると、 `tests` に格納されたテストケースを `t := tests[_]` で1つずつ取り出し、検査していくという手法をとっています。Regoは基本的に状態を持たず、入力に対して一意の結果を返させるという使いかたが主なため、table driven testとも相性がいいと考えられます。

この記述方法のポイントは `test_authz` でテストをせず、 `authz_failed_results` 内で失敗するテストを探索し、失敗したテストがなかった（ `count(authz_failed_results) == 0` ）場合にテスト成功と判定しているところです。これは `test_authz` で `t := tests[_]` を使って検査した場合、１つでも一致するものがあると `test_authz` は成功したとみなされる、すなわちテストはPassしたとみなされてしまうためです。これを回避するために１つでも失敗するテストケースがあったら失敗する、というような検証をする必要があるわけです。

記述量の面でいうと普通にテストを書いた場合とそれほどかわりありませんが、テストの条件がまとまっていて見やすい点、およびテスト失敗時のメッセージを自由にカスタマイズできるというメリットがあります。例えば、上記の例だと以下のようなメッセージが出力されます。

```
failed test 'other than /v1/data is not allowed'. expected true, but got false
```

この他にもテストの入力値を表示させるなどにより、なぜテストが失敗したのかがわかりやすくすることができます。


[^trace]: テスト失敗時にスタックトレース的なものは表示されるのですが、パッと見で何が失敗しているのかは判別しづらいです。