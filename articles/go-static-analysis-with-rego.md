---
title: "OPA/Regoによる汎用的なGo言語の静的解析"
emoji: "👻"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "opa", "rego"]
published: true
---

# TL; DR

- Go言語は様々な静的解析ツールがあるが、独自ルールのチェックなどをするには都度ツールを自作する必要がある
- 1つのツールでより汎用的なチェックができるように、汎用ポリシー言語のRegoでGo言語のAST（抽象構文木）を検査できるようにした

https://github.com/m-mizutani/goast

![](https://storage.googleapis.com/zenn-user-upload/0356521438bb-20220911.png)
*「第一引数に必ずcontext.Contextをとる」というルールをCIでチェックした様子*

# 背景

Go言語では様々な静的解析ツールが提供されており、一般的なベストプラクティスが正しく記述されているか？については既存の静的解析ツールを利用することで概ね必要なチェックをすることができます。例えばセキュアなGoのコーディングをするためのツールとして [gosec](https://github.com/securego/gosec) などがあり、自分も愛用させてもらっています。しかし、ソフトウェア開発におけるコーディング上のルールはベストプラクティスによるものだけでなく、そのソフトウェアやチームに依存したルールというのも起こりえます。例えば次のようなルールです。

- あるパッケージでは全ての関数の引数に `context.Context` をとらなければならない
- あるパッケージでは全ての関数内で監査用のログを出力する関数が最低1度は呼ばれていないといけない
- `User` という構造体は必ず `NewUser()` という関数によって初期化されないといけない
- ある関数は特定のパッケージ内でしか呼ばれてはならない

これらのルールはレビュー時に人間がチェックすることもできますが、[人間はつねにミスをする可能性がある](https://www.igaku-shoin.co.jp/paper/archive/y2021/3433_01)ため人間だけに頼るのは難しいです。また、ルールが少ないうちはレビューによるチェックが機能していても、ルールが多くなることで注意が散漫になりうっかり見逃してしまう可能性が高くなります。また、本質的なレビューへも集中できなくなってしまいます。

機械的にチェックをする場合、たしかにGo言語は静的解析のためのツールやフレームワークが公式から提供されているのもあり、ツールの自作はやりやすい環境にあると言えます。しかし一方でルール毎に解析ツールを作成するというのは、実装やメンテナスのコストからするとやや厳しいように感じます。そこでなるべく汎用的に静的なコードのチェックができるツールができないかと考えました。

# Regoでルールと実装を分離する

静的解析に限った話ではありませんが、汎用性の高いチェックツールを作ろうとした場合、ユーザにルールをどのように記述させるかが一つのポイントになってきます。独自の記述言語を作るのはあまりにもコストが高いですし、YAMLやJSONなどの構造データでルールを与えようとすると表現力が限られてしまい、汎用性は下がってしまいます。

このような用途で役立つ道具として、ポリシー記述言語の [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/) があげられます。Regoは汎用的な目的で利用できる言語となっており、[OPA](https://github.com/open-policy-agent/opa) というエンジンを使って構造データの評価をします。有名な利用方法としては、クラウド環境で使われるリソース状況のチェック、Infrastructure as Code で記述された内容のチェック、サーバへのアクセスに対する認可のチェックなどの例があります。詳しくは[OPA/Rego入門](https://zenn.dev/mizutani/books/d2f1440cfbba94)を御覧ください。

Regoを使うことでチェックする実装とルールを完全に分離できます。実装はファイルの読み込みやポリシーの読み込み、評価用データの受け渡しや、評価結果をどう出力するかを担い、ルールはRegoのみで記述します。これによってツールを実装する人とルールを考える人で興味を分割することができます。

# 実装

ということで実装したのが `goast` [^naming]というツールです。

https://github.com/m-mizutani/goast

Goのコードを読み込み、コードの抽象表現であるAST（Abstract Syntax Tree、構文抽象木）をRegoで記述されたポリシーによって評価します。ASTに関する説明は[こちら](https://docs.google.com/presentation/d/11szCB0AyyjjeaiTFlLCWOMd0pIlpqukgHmht7FGwjO8/edit#slide=id.g5d2856d934_0_270)の資料などがわかりやすいかと思います。 `parser` パッケージを使ってGoソースコードのASTを取得し、これをRegoのポリシーで評価します。評価はファイル全体のASTを一度だけ渡す、あるいはASTのノード毎に評価するモードを用意しています。

## ASTを確認する

具体的な使い方をみていきましょう。自分もGoのASTについては初心者なので、コードを見ただけではASTが全くイメージできません。そのため `goast` には確認用にASTをダンプする機能をつけました。

```go
package main

import "fmt"

func main() {
        fmt.Println("hello")
}
```

このコードに対して以下のコマンドでASTを出力します。

```bash
$ goast dump --line 6  examples/println/main.go | jq
{
  "Path": "examples/println/main.go",
  "Node": {
    "X": {
      "Fun": {
        "X": {
          "NamePos": 44,
          "Name": "fmt",
          "Obj": null
        },
        "Sel": {
          "NamePos": 48,
          "Name": "Println",
          "Obj": null
        }
      },
      "Lparen": 55,
      "Args": [
        {
          "ValuePos": 56,
          "Kind": 9,
          "Value": "\"hello\""
        }
      ],
      "Ellipsis": 0,
      "Rparen": 63
    }
  },
  "Kind": "ExprStmt"
}
```

ASTの構造データは比較的大きくなりやすく、先述した7行程度のコードでも1,408文字のJSONデータとなります。そのためみやすさ重視でコードの6行目（ `fmt.Println("hello")` ）の部分だけを出力するよう指定しました。`Path` は読み込んだファイルパス、`Node` は [ast.Inspect](https://pkg.go.dev/go/ast#Inspect) によって渡された `ast.Node` をそのままダンプ[^object]したもの、そして `Kind` は `Node` の型情報になります[^type]。

何となく想像できるかなと思いますが、ここでは `.Node.X.Fun` が呼び出し元の関数の情報を、`.Node.X.Args` が引数を表しています。例えばこれを使えば、「特定の関数の呼び出しを禁止する」というようなルールを記述することができます。さらに発展形として、

- 特定のパッケージ内で呼び出しを許可する・禁止する
- 特定の引数を許可する・禁止する
- リテラルを直接渡すことを許可する・禁止する

などの条件を組み合わせて記述することもできます。

## ルールを記述する

では出力されたASTからRegoのルールを記述してみましょう。今回はシンプルに `fmt.Println` の呼び出すを禁止する、としてみます。

```rego
package goast

fail[res] {
    input.Kind == "ExprStmt"
    input.Node.X.Fun.X.Name == "fmt"
    input.Node.X.Fun.Sel.Name == "Println"

    res := {
        "msg": "do not use fmt.Println",
        "pos": input.Node.X.Fun.X.NamePos,
        "sev": "ERROR",
    }
}
```

goastはポリシーの記述にはいくつかのルールがあります。

- `package` が `goast` でなければならない
- 入力： `input` には `Path`、`Kind` のようなメタ情報と、実際のASTである `Node` が渡される
- 出力：違反があった場合、 `fail` という変数に以下のフィールドをもつ構造体を入れる
  - `msg`: 違反内容のメッセージ（文字列）
  - `pos`: ファイル内の位置を示す整数値
  - `sev`: 深刻度。`INFO`, `WARNING`, もしくは `ERROR`

まず、先程の `fmt.Println` を検出するのがルール冒頭の3行です。Regoには先程ダンプした形式のメッセージがそのまま `input` に渡されるため、`Kind`、`Node.X.Fun.X.Name`、`Node.X.Fun.Sel.Name` を検査することで関数呼び出しの式であることを判定できます。

それ以降の部分は違反の内容を知らせるための情報となります。ASTに慣れていないと `pos` の意味がわかりにくいかもしれませんが、今回の場合はファイルの先頭から何バイト目かを示す数値になっており[^pos]、`NamePos` や `ValuePos` というフィールドに格納されています。これを応答に含めてもらうことで、 goast側で違反があったファイルの行数に変換し、最終的な出力で行数を示すことができるようになります。

さきほどのGoのコードを `main.go`、ルールを `policy.rego` として保存し、以下のように実行することで違反を検出できます。

```bash
$ goast eval -p policy.rego main.go
[main.go:6] - do not use fmt.Println

        Detected 1 violations

```

また、JSON形式での出力にも対応しています。

```bash
$ goast eval -f json -p policy.rego main.go
{
  "diagnostics": [
    {
      "message": "do not use fmt.Println",
      "location": {
        "path": "main.go",
        "range": {
          "start": {
            "line": 6,
            "column": 2
          }
        }
      }
    }
  ],
  "source": {
    "name": "goast",
    "url": "https://github.com/m-mizutani/goast"
  }
}
```

## CIで使う

静的解析はCI（Continuous Integration）によって継続的に実施することで、意図しないコードの混入を防ぐ役割を発揮します。先程のJSON出力のスキーマは[reviewdog](https://github.com/reviewdog/reviewdog)に準拠しており、そのままreviewdogで利用することができます。

GitHub Actions で利用できる[goast-action](https://github.com/m-mizutani/goast-action)も用意しており、以下のようなworkflowでPull Requestに対して静的検査を実施できます。

```yaml
name: goast

on:
  pull_request:

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - name: checkout
        uses: actions/checkout@v2
      - uses: reviewdog/action-setup@v1
      - name: goast
        uses: m-mizutani/goast-action@main
        with:
          policy: ./policy  # Regoで記述されたルールがあるディレクトリ
          format: json      # 出力形式
          output: fail.json # 結果を書き出すファイル
          source: ./pkg     # 検査する対象のGoソースコードがあるディレクトリ
      - name: report
        env:
          REVIEWDOG_GITHUB_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: cat fail.json | reviewdog -reporter=github-pr-review -f rdjson
```

これが実行されると、違反を検出した場合は以下のような感じでコメントがつきます。

![](https://storage.googleapis.com/zenn-user-upload/0356521438bb-20220911.png)

# まとめ

汎用的なポリシー言語RegoをGo言語の静的解析に用いることで、（ASTに関する理解は必要になるものの）より静的解析に取り組みやすくなったのではと考えています。これによってよりソフトウェア開発が堅牢かつ安全なものになっていけばと期待しています。

もともとソースコードの静的解析（というかlint）で汎用ポリシー言語であるRegoを使うという発想自体は、別の方も過去にも取り組まれていた[^sql]ものですが、自分がよく使う開発言語でもそれを実現できるようになったのは良かったかなと考えています。

ただ、ソースコードの全体像を示すASTと汎用的なポリシー言語であるRegoを使えば全ての静的検査がカバーできるのでは？と言われるとそうでもありません。例えばRegoは状態の変化を追跡するようなルールを書くのは苦手なので、例えば「ある変数がどのように参照・変更されたか」というユースケースにはあまり適さないと考えられます。

# 2022.9.19 追記

続編書きました。

https://zenn.dev/mizutani/articles/go-static-analysis-with-rego-ex

まだ自分でも実践で使い始めたばかりなので、いろいろ探りながら使っている段階です。機能提案などは歓迎ですので、お気軽にコメントや[issue立て](https://github.com/m-mizutani/goast/issues/new)などしてもらえればと思います。

[^sql]: https://zenn.dev/takenokogohan/articles/90655d509a21c1
[^naming]: 言わずもがな GO + AST です。スペルミスではないよ
[^object]: GoのASTに詳しい人はご存知かもしれませんが、本来は `Obj` のポインタの先にその定義体の宣言元などに関する情報が入っています。しかしこれは内部で循環参照が発生しているため、そのままダンプしようとすると無限ループ、ないしはstack overflowを起こしてしまいます。そのため `goast` では `Obj` のフィールドだけ無視してコピーするような機能を実装し、都度ノードを評価前にコピーしています。ただ、 `Obj` 内の情報が必要になるケースもあるかと考え、回数制限ありで再帰する `--object-depth` というオプションも用意しています。
[^type]: 本来、静的解析する際は型情報をもったままinterfaceとして渡されるので、Type switchによって型を判定できるのですが、JSONにした瞬間何もわからなくなってしまうので、せめて最上位ノードの型情報だけはつけるようにしました。
[^pos]: Posの詳しい説明はこちらの記事が参考になるかと思います https://qiita.com/tenntenn/items/13340f2845316532b55a