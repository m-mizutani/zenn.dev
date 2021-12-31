---
title: "⚙️ Go言語によるRego runtimeの組み込み"
---


この節ではGo言語からRegoのruntimeを呼び出し、ポリシーの評価結果を求める手順について解説します。

# セットアップ

まずはGoの開発環境をセットアップしてください。この記事では以下の環境で検証しています。

- go: `1.17.2 darwin/arm64`
- opa: `v0.34.2`

Go開発環境のセットアップについては以下のページなどをご参照ください。

- https://go.dev/doc/install

準備ができたら以下の通りモジュールの準備をします（下記の解説では `regotest` を作業用ディレクトリと仮定しますが、別の名前でも問題ありません）

```sh
$ mkdir regotest
$ cd regotest
$ go mod init regotest
$ go get github.com/open-policy-agent/opa/rego
```

# Regoランタイムの利用

まずはシンプルな具体例から見ていきたいと思います。以下のコードを `main.go` として `./regotest` 以下に保存します。

```go:main.go
package main

import (
	"context"
	"fmt"

	"github.com/open-policy-agent/opa/rego"
)

func main() {
	input := struct {
		User string `json:"user"`
	}{
		User: "mizutani",
	}

	module := `package blue

	allow {
		input.user == "mizutani"
	}
	`

	q := rego.New(
		rego.Query(`x := data.blue.allow`),
		rego.Module("module.rego", module),
		rego.Input(input),
	)

	rs, err := q.Eval(context.Background())
	if err != nil {
		panic(err)
	}

	fmt.Println("allow =>", rs[0].Bindings["x"])
}
```

goコマンドで実行すると以下のような結果が得られると思います。

```sh
$ go run .
allow => true
```

Goの基礎的な部分についての詳細は省き、Regoに関する部分を解説します。

## クエリ、モジュール、入力の設定

```go
	q := rego.New(
		rego.Query(`x := data.blue.allow`),
		rego.Module("module.rego", module),
		rego.Input(input),
	)
```

`rego.New` メソッドによってランタイムを生成します。Functional Option Patternなので任意の数・種類のオプションを渡すことができますが、`rego.Query` だけはかならず必要です。この生成方法だとクエリ、およびモジュールの文法ミスが実行時までわからないので、先に検出したい場合は[Compiler](https://pkg.go.dev/github.com/open-policy-agent/opa/rego#example-Rego.Eval-Compiler)を利用することもできます。

クエリとモジュールの関係は[Regoの基礎（パッケージ編）]()で解説したとおりです。モジュールに記述されたルール群をクエリで指定して呼び出した結果を返します。上記の例では `x := data.blue.allow` というクエリにして `x` に `blue` モジュールの `allow` の結果を割り当てていますが、 `data.blue.allow` とだけすることで、式の評価結果だけを取り出すこともできます。（詳しくは後述）

入力はJSON形式に一度変換してからRegoで処理されます。そのため、構造体から渡す場合には `json` タグで指定されたフィールド名で処理されます。また、テキスト形式で受け取ったJSONデータの場合は `interface{}` の変数を用意して一度unmarshalする必要があります。

## 評価結果の取得と処理

```go
	rs, err := q.Eval(context.Background())
	if err != nil {
		panic(err)
	}
```

`Eval()` を呼び出すことでポリシーの評価結果（およびエラー）を取得できます。評価結果は `rego.ResultSet` (`rego.Result` の配列) で返されます。これはクエリで `data.allowed_users[x]` のように指定すると、条件に一致する結果をすべて返すことになるため、複数の評価結果を扱えるようになっています。これについてはモジュール側に任意のポリシーが記述されても、クエリ側で返される結果の数をある程度制御できます。ただし、クエリで指定した評価結果に偽が含まれる場合は何も値が返されず、`ResultSet` は0個になります。

```go
	input := struct {
		User string `json:"user"`
	}{User: "x"}

	module := `package blue
	allow {
		input.user == "mizutani"
	}`

	q := rego.New(
		rego.Query(`x := data.blue.allow`),
		rego.Module("module.rego", module),
		rego.Input(input),
	)

	rs, err := q.Eval(context.Background())
	if err != nil {
		panic(err)
	}

	fmt.Println("rs =>", len(rs)) // rs => 0
```

評価の結果は `rego.Result` 内にある `Expressions` および `Bindings` の2つのフィールドに保持されます。

- `Expression`: クエリ内で評価された式についての結果を保持します。例えばクエリが `data.blue` だけなら `blue` パッケージ内で発生した結果（ `{"allow":true}` ）がこの中に格納されます。`x := data.blue` のようにしても式の評価結果自体は残るのですが、こちらは「代入」という処理の結果として 値が入れば `true` が記録されるのみになります。
- `Bindings`: クエリ内で新たに値が割り当てられた変数の

例えば式だけクエリに記述すると、

```go
	q := rego.New(
		rego.Query(`data.blue`),
		rego.Module("module.rego", module),
		rego.Input(input),
	)

	rs, err := q.Eval(context.Background())
	if err != nil {
		panic(err)
	}

	pp.Println(rs)
```

このように、 `rs[0].Expressions[0].Value["allow"]` に結果が格納されます。

```go
rego.ResultSet{
  rego.Result{
    Expressions: []*rego.ExpressionValue{
      &rego.ExpressionValue{
        Value: map[string]interface {}{
          "allow": true,
        },
        Text:     "data.blue",
        Location: &rego.Location{
          Row: 1,
          Col: 1,
        },
      },
    },
    Bindings: rego.Vars{},
  },
}
```

一方でクエリを `x := data.blue` とすると、新たに割り当てられた `x` に関する結果が `rs[0].Bindings["x"]` に格納されるのがわかります。式は前述の通り、`true` のみが格納されます。

```go
rego.ResultSet{
  rego.Result{
    Expressions: []*rego.ExpressionValue{
      &rego.ExpressionValue{
        Value:    true,
        Text:     "x := data.blue",
        Location: &rego.Location{
          Row: 1,
          Col: 1,
        },
      },
    },
    Bindings: rego.Vars{
      "x": map[string]interface {}{
        "allow": true,
      },
    },
  },
}
```

# 参考文献

- Integrating with the Go API https://www.openpolicyagent.org/docs/latest/integration/#integrating-with-the-go-api
- rego package: https://pkg.go.dev/github.com/open-policy-agent/opa/rego#pkg-examples
