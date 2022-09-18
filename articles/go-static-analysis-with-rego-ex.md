---
title: "OPA/Regoによる汎用的なGo言語の静的解析（実践編）"
emoji: "🎃"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "opa", "rego"]
published: true
---

# これまでのあらすじ

https://zenn.dev/mizutani/articles/go-static-analysis-with-rego

前回執筆した記事がなかなかの好評をいただけたようなので、今回はより実践的な内容の説明をしたいと思います。前回の記事では全体イメージのわかりやすさ優先で細かい説明を端折っていました。今回は実際にどのようにASTを評価するのか、どのようなルールが書けるのか、テストはどうするのか、などについて説明します。

# goastによるソースコード検査の仕組み

まずはじめにgoastがどのような仕組みでGoのソースコードを検査するかの仕組みについて簡単に説明します。Goは[astパッケージ](https://pkg.go.dev/go/ast)によってソースコードをparseすることで、Abstract Syntax Treeを作成します。非常に大雑把ではありますが、イメージとしては下図のようになります。

![](https://storage.googleapis.com/zenn-user-upload/10a1f5bb4d89-20220916.jpg)

いろいろと省略していますが、基点となる構造体が `ast.File` というファイル全体を示すノード（`ast.Node` interface）となっており、その子供にトップレベルで宣言された関数や変数などの定義、そしてさらにその子供に関数内の式などが格納されています[^ast]。

goastはこれらのノードを巡回し[^inspect]、Regoで記述されたルールを用いて評価していきます。例えば、`ast.File` (ファイル全体) → `ast.FuncDecl` (関数の定義) → `ast.AssignStmt` (変数の代入) という流れで一つずつ評価します。もちろん、`ast.File` からはそのファイル内の全てのノードへリンクされており参照可能ですが、Regoが再帰表現が苦手なこと、またネストされたノードの型情報がRegoへデータを引き渡す際に落ちてしまう、という理由で巡回するようにしました。

巡回する際には `input.Kind` に型情報が入るようになっています。なので特定の型のノードに対してのみルールの評価をしたい場合、例えば `input.Kind == "FuncDecl"` という条件を入れておくことで、関数の宣言だけを評価できるようになります。

# ルールの記述例

goastのルールを記述するためにはGo言語のASTについての理解だけでなく、Regoの文法や記述方法への理解も必要です。そのためルールの記述は一定ハードルが高くなってしまうため、参考となりそうなルールの記述例を紹介したいと思います。

実際のRegoファイルは以下のリポジトリに置いてあるので、よろしければ御覧ください。
https://github.com/m-mizutani/goast-example/tree/main/.goast

goastのルールは「違反している状態」を記述し、その状態に一致するコードが発見されたときに違反として報告されます。

## ルール例1) 構造体の生成にコンストラクタを使っているかを検証するルール

生成する際になんらかの初期化処理が必要な構造体は、変数を直接宣言するのではなく初期化用の関数（コンストラクタ）を使うようにしたい、というユースケースです。例えば `User` を生成するために `NewUser` のような関数を使わせたい、というイメージです。

必ずコンストラクタを使う≒変数を宣言したり代入させたりしない、ということになるかと思います[^construct]。そこで、変数の宣言・代入を検出するルールを記述して適切に初期化されてない変数の排除を試みます。

```rego
# var user model.User での宣言を検出
fail[out] {
	input.Kind == "DeclStmt"
	spec := input.Node.Decl.Specs[_]
	spec.Type.X.Name == "model"
	spec.Type.Sel.Name == "User"

	out := {
		"msg": "User must be created with constructor",
		"pos": spec.Type.X.NamePos,
	}
}

# user := model.User{} での代入を検出
fail[out] {
	input.Kind == "AssignStmt"
	n := input.Node.Rhs[_]
	n.Type.X.Name == "model"
	n.Type.Sel.Name == "User"

	out := {
		"msg": "User must be created with constructor",
		"pos": n.Type.X.NamePos,
	}
}

# user := &model.User{} での代入を検出
fail[out] {
	input.Kind == "AssignStmt"
	n := input.Node.Rhs[_]
	n.X.Type.X.Name == "model"
	n.X.Type.Sel.Name == "User"

	out := {
		"msg": "User must be created with constructor",
		"pos": n.X.Type.X.NamePos,
	}
}
```

宣言は `DeclStmt`、代入は `AssignStmt` でそれぞれ検出できます。外部パッケージの型の参照は `Type.X.Name` にパッケージ名、`Type.Sel.Name` に構造体名が入ります。

今回はわかりやすさ重視でナイーブな書き方にしていますが、もう少し重複部分を排除した記述もできます。

## ルール例2) 関数の第一引数に context.Context を持っているかを検証するルール

外部I/Oなどでブロッキングされるような関数はcontext.Contextを引数に持たせ、さらに第一引数にするという実装を多く見ます。これを機械的にチェックするルールもRegoで記述できます。

```rego
package goast

fail[res] {
	input.Kind == "FuncDecl"
	not has_context(input.Node.Type.Params.List)

	res := {
		"msg": "first argument must be context.Context",
		"pos": input.Node.Name.NamePos,
	}
}

has_context(args) {
	args[0].Type.X.Name == "context"
	args[0].Type.Sel.Name == "Context"
}
```

このルールのコツは第一引数が `context.Context` であることのチェックを `has_context` という関数に外だししているということです。Regoのポリシーの評価は記述された式をそれぞれ評価し、一つでも式の評価が失敗したらポリシー全体の評価が失敗した、とみなします。この際、「失敗」は `"a" != "b"` のような比較などの結果だけでなく、構造データへ参照できなかった場合も「失敗」とみなされます。このケースだと、

```
fail[res] {
	input.Kind == "FuncDecl"
	args := input.Node.Type.Params.List
	args[0].Type.X.Name == "context"
	args[0].Type.Sel.Name == "Context"
```

と書けそうと直感的に思うかもしれません。しかし、Regoは下記のケースも「評価が失敗した」と判定されます。

- `args` の配列の長さが0の場合：つまり引数なし
- `args[0].Type.X.Name` が無い場合：例えば `int` 型の場合は `args[0].Type.Name` に `int` が格納される

これによって、ポリシー全体の評価が失敗した＝違反はなかった、と判定されてしまいます。これを回避するために `has_context` に条件を切り出し、`not has_context` として呼び出します。これによって `args[0].Type.X.Name == "context"` と `args[0].Type.Sel.Name == "Context"` のどちらか、あるいは両方が失敗した場合に、**評価結果が成功となる** ルールが記述できるというわけです。

このルールをRegoで記述する良さは、追加の条件を柔軟に記述できることです。例えば

- 特定の関数名は許可する（allow list）
  - 派生系1) 特定のプレフィックスを持つ関数だけ許可する
  - 派生系2) エクスポートしている関数のみチェックする
- `context.Context` の他にも許可する引数の型を追加する
- 特定のディレクトリ下のファイルだけチェックする

などの条件を記述できます。全ての関数が `context.Context` を持つべき、とはならないと思うのでチームなどの都合に合わせて調整ができます。

## ルール例3) 最低一度はある関数が呼ばれているかを検証するルール

1つの関数内で **ある別の関数** が最低一度は呼ばれたかを検証します。例えばメインのビジネスロジックをまとめたパッケージ内では、各ビジネスロジック（関数）を処理する際に必ず監査用のログ出力用の関数を呼び出さなければいけない、というようなユースケースを想定しています。

```rego
package goast

import future.keywords.every

fail[res] {
	input.Kind == "FuncDecl"
	every stmt in input.Node.Body.List {
		not is_log_func(stmt.X.Fun)
	}

	res = {
		"msg": "utils.Log must be called at least once",
		"pos": input.Node.Name.NamePos,
	}
}

is_log_func(f) {
	f.X.Name == "utils"
	f.Sel.Name == "Log"
}
```

関数ごとにチェックをするため、 `FuncDecl` のノードを検査しています。関数内の記述は `input..Node.Body.List` に格納されており、その中に1つも該当する特定の関数（ルール中の例だと `utils.Log` という監査用ログ出力関数）がなかったら違反とみなします。

`every` 句は配列から要素を一つずつとりだして、全ての要素が評価に成功するかをチェックします。 `is_log_func` を使っているのは先程の `has_context` と同じ理由です。

# テストの準備

静的解析の話に限らずポリシーのコード化、すなわち [Policy as Code](https://docs.hashicorp.com/sentinel/concepts/policy-as-code) の利点の一つはテストを記述しやすくなることです。テストによって、記述したルールが意図したとおりに違反を検出するか、あるいは違反ではないコードを誤検知しないか事前に確認できます。さらに自動で実行できれば繰り返し確認できます。

goastのルールをテストするにあたって難しいのはテスト用データの整備かと思います。 `dump` サブコマンドによってGoコードの特定の関数や行のASTを出力できますが、行指定だと元のコードをいじった場合に対象の行がずれたり、関数名だとASTとする対象が広がりすぎたりと使い勝手が悪くなります。

そこでgoastでは `sync` というサブコマンドも用意しました。コード中に `goast.sync: <パス名>`  記述することで、該当行のASTを指定したファイルへ出力します。具体的には次の応用に記述します。

```go
package main

import "context"

func HasContext(ctx context.Context, a, b int) int { // goast.sync: .goast/testdata/args/has_context/data.json
	return a + b
}

func NoContext(a, b int) int { // goast.sync: .goast/testdata/args/no_context/data.json
	return a + b
}

func NoArgs() int { // goast.sync: .goast/testdata/args/no_args/data.json
	return 0
}
```

このようなファイルを用意した上で、

```bash
$ goast sync <読み込むGoソースコードファイル、あるいはディレクトリ>
```

として実行することで、 `.goast/testdata/args/no_context/data.json` などのファイルにASTが保存されます。

# テストの記述

これを使ってRegoのテストを記述します。下記のテストを `.goast/use_context_test.rego` として保存したとします。（ルールについては `.goast/use_context.rego` に記述されているものとします）

```rego
package goast

test_use_context_has_context {
	out := fail with input as data.testdata.args.has_context
	count(out) == 0
}

test_use_context_no_context {
	out := fail with input as data.testdata.args.no_context
    out[_].msg == "first argument must be context.Context"
}

test_use_context_no_args {
	out := fail with input as data.testdata.args.no_args
    out[_].msg == "first argument must be context.Context"
}
```

Regoのテストでは `with input as <任意のデータ>` とすることで、入力値を差し替えることができます。また、ポリシーファイル（ `*.rego` ファイル）のディレクトリ以下にあるJSONファイルが自動的に `data` に読み込まれます。読み込み時のパスは相対になる、かつディレクトリ単位で読み込まれるため、 `.goast/testdata/args/has_context/data.json` は `data.testdata.args.has_context` としてアクセスできます。

上記のテストコードでは、

- `test_use_context_has_context`: 違反が検出さない
- `test_use_context_no_context`: 違反
- `test_use_context_no_args`: 違反

になるよう想定されており、それぞれ

- `count(out) == 0` で違反が検出されなかったことをテスト
- `out[_].msg == "first argument must be context.Context"` で狙った違反が検出されていたかをテスト（狙っていない違反も含まれる場合があるため）

するようにしています[^pos]。

# テストの実行

ここまで準備できたらあとはOPAでテストを実行[^test]します。

```bash
$ opa test -v .goast
.goast/use_context_test.rego:
data.goast.test_use_context_has_context: PASS (238.291µs)
data.goast.test_use_context_no_context: PASS (224.583µs)
data.goast.test_use_context_no_args: PASS (190.542µs)
--------------------------------------------------------------------------------
PASS: 3/3
```

このテストはあくまで検査用のポリシーが正しく機能するかをチェックするものなのです。なので例えば開発しているプロダクトのリポジトリで `.goast` 以下にポリシーなどを配置している場合、`.goast` 以下のファイルに変更があった場合にCIを実行する、などでも良いかもしれません。

# まとめ

自分で作っておいてなんですが、Go言語のASTとRegoの組み合わせは不慣れだとなかなかに難しいと思います。もし使ってもらえる人がいそうならなるべく足がかりとなりそうな解説が必要かと思い、続編として実践編を執筆してみました。

もし「使ってみたいんだけど、こういうルールはどう書くんだろう」というのがあれば、できる範囲でサンプルルールを用意したりなどサポートをしたいと考えていますので、お気軽にお声がけください。

[^ast]: 実際にはより多くの情報が格納されている＆フィールドもあえて省略して記載しているので、詳しくはgo/astの実装を見てください。 https://pkg.go.dev/go/ast
[^inspect]: 巡回自体は[ast.Inspect](https://pkg.go.dev/go/ast#Inspect)を使っています。
[^construct]: という認識なのですが、抜け漏れあったら気づいた方教えて下さい
[^pos]: より正確にやるためには `out[_].pos` をチェックして違反の検出位置を照合すると良いのですが、これはコード側を少しでもいじるとあっという間に値が変わってしまいメンテコストが高くなってしまうので、今回の例では入れていません。
[^test]: テストの仕組み自体をgoastに入れ込むことも検討しましたが、元々のOPAのテスト機能に頼ったほうが良いと判断し、`sync` サブコマンドでテスト用データを出力するに留めました。ただ、今後テスト機能も統合したほうが良さそうとなったら検討したいと考えています。