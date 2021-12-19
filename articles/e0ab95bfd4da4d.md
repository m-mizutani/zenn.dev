---
title: "Regoのコーディング規約をRegoで検査する"
emoji: "🔁"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["opa", "rego"]
published: true
---

この記事は[OPA/Regoアドベントカレンダー](https://adventar.org/calendars/6601)の20日目です。

本アドベントカレンダーの[OPAコマンドの利用](https://zenn.dev/mizutani/articles/f00d3ca12e4102) でも紹介しましたが、 `opa` コマンドは様々な機能を有しており、その中にコードのチェックに関するサブコマンドも含まれています。`check` はポリシーやデータに言語としての論理的な不整合がないかを事前チェックし、`fmt` は改行やインデントなどのフォーマットを修正してくれます。しかし、それ以外のコーディングに関する規約のチェックをするような機能は現状 `opa` コマンド自身には無いようです。

OPAのルールを複数人で管理するとなると、（主に筆者の経験から）例えば以下のような項目を強制して管理しているリポジトリの治安を維持したくなります。

- 保存時にはデバッグ用の `print` を残さないようにする（ `trace` は許可）
- 1つのパッケージを1つのディレクトリに集約し、複数ディレクトリに散らばらないようにする
- パッケージにごとに必ずテストを1つ以上記載する
- 変数名や関数名をsneak case、もしくはcamel caseのどちらかで統一する（おそらく一般的にはsneak case）
- 非推奨の `=` [^equality]を使わず、`:=` と `==` のみを使う
- イテレーションに用いる変数は必ず `some` キーワードで宣言する
- 特定のポリシー間で参照を禁止する

これに加えて組織ごとに管理の方針があると、さらにカスタマイズした制約が発生すると思われます。開発経験のある方はわかると思いますが、複数人でコードをいじる以上「気をつける」だけではルールの徹底はむずかしく、CIのテストなどで制御するべきでしょう。

残念ながら（ざっと調べた限りだと）現状はそういったRegoのlinterツールはないようです。ではlinterの登場を待つべきかといえば、その必要はありません。このアドベントカレンダーでずっと紹介してきた柔軟かつ記述力に優れたポリシー言語があります。そう、 **Regoを使ってRegoのコーディング規約をチェック** すればいいのです。

# アプローチ

`opa` にはチェックの機能の他に `parse` サブコマンドがあり、OPA内で扱われているRegoの抽象構文木（AST）が出力されます。サンプルのポリシーとして `policy.rego` を用意します。

```rego:policy.rego
package linttest

allow {
	input.user == "blue"
}
```

これをparseすると以下のような出力が得られます。

```bash
$ opa parse -f json policy.rego
{
  "package": {
    "path": [
      {
        "type": "var",
        "value": "data"
      },
      {
        "type": "string",
        "value": "linttest"
      }
    ]
  },
  "rules": [
    {
      "head": {
        "name": "allow",
        "value": {
          "type": "boolean",
          "value": true
        }
      },
      "body": [
        {
          "terms": [
            {
              "type": "ref",
              "value": [
                {
                  "type": "var",
                  "value": "equal"
                }
              ]
            },
            {
              "type": "ref",
              "value": [
                {
                  "type": "var",
                  "value": "input"
                },
                {
                  "type": "string",
                  "value": "user"
                }
              ]
            },
            {
              "type": "string",
              "value": "blue"
            }
          ],
          "index": 0
        }
      ]
    }
  ]
}
```

詳細を説明すると長くなってしまうので割愛しますが、パッケージ名、変数の情報、操作内容、そして全体の構造が取得できていることがわかるかと思います。

OPAは[乱暴に言うと](https://zenn.dev/mizutani/articles/69553e82b34c20#%E5%85%B7%E4%BD%93%E7%9A%84%E3%81%AA%E6%A9%9F%E8%83%BD)「ポリシー（Rego）に従って入力されたJSONを別のJSONで出力するためのエンジン」なので、このデータをそのままOPAで処理すれば解決、となりそうですがこのままだといささか不都合があります。`parse` コマンドは原則1ファイルしか解析・出力ができない＆ASTそのもの歯科出力できないため、以下の問題が起こります。

- **複数ファイルを同時にチェックできない**: ファイル間の依存関係や、パッケージ内についての規約（例えばテストのある無しなど）については複数ファイルを同時に評価する必要があります。OPAは基本的に1つの構造データしか受け付けられず、つまり複数のJSONデータを1度に検証できません。
- **ファイルに関するメタな情報が得られない**: 渡ってきたJSONデータがASTのみだとファイルパスが得られないため、ファイル配置に関する規約については検証できません。

もちろん、全Regoファイルのparseをする → ファイルのメタ情報を付与する → 全てのファイルの情報を結合する、という処理をするスクリプトを個別のリポジトリに用意するという方法はあります。が、共通して使いそうな機能を個々で管理するのは効率が悪そうということで、コンセプト実装を作ってみました[^issue]。

# regolint

https://github.com/m-mizutani/regolint

実装をみるまでもないんですが、やっていることは

- 全Regoファイルのparseをする
- ファイルのメタ情報を付与する
- 全てのファイルの情報を結合する

だけなので非常にシンプルです。`-p` オプションでファイル or ディレクトリを指定すると、

```json
[
  {
    "path": [
      "regotest",
      "policy.rego"
    ],
    "rego": {
      "package": {
        "path": [
          {
            "type": "var",
            "value": "data"
          },
          {
            "type": "string",
            "value": "regotest"
          }
        ]
      },
=== 割愛 ====
```

というデータが指定されたポリシーによって評価され、もし違反があった場合は以下のように表示されます。

```bash
% regolint -p ./example/policy/example.rego ./example/
Failed
example/regotest/policy.rego: package path and directory path is not matched
17:22:12.478 [error] got evaluation failure
```

# ルール例

では具体的にどのようなポリシーが書けるのが見てみましょう。ポリシーの書き方は[こちら](https://github.com/m-mizutani/regolint#parameters)にもありますが、以下のとおりです。

- パッケージ名: `regolint` にする
- 入力(`input`): `files`
    - `path` OSごとの区切り文字で分割されたファイルパス（文字列の配列）
    - `rego` Regoのポリシー（構造は[OPAのコード](https://github.com/open-policy-agent/opa/blob/main/ast/policy.go)にある `ast.Module` を参照）
- 出力: `fail[msg]` にポリシー違反の情報を格納する

```rego:example/policy/example.rego
# Check file path
fail[msg] {
    file := input.files[_]
    count(file.path) <= 1
    msg := sprintf("%s: .rego file at top level is not allowed", [concat("/", file.path)])
}
```

まずひとつ目のポリシーはトップレベル（つまり `./example` 直下）にポリシーが置かれていないかのチェックです。こちらは比較的シンプルで、読み込んだ際のファイルパスの長さをチェックしています。こちらの `path` はOSごとに異なるディレクトリのセパレータの処理をさせるのは不毛なので、事前にディレクトリおよびファイル名を分割して配列にして渡しています。これが1以下、つまりファイル名のみという場合はトップレベルに置かれているという判定になります。もちろんトップレベルに配置すること自体は問題ないのですが、そのようなルールになっていた場合という想定です。

```rego:example/policy/example.rego
# Check matching with directory path and package path
fail[msg] {
    file := input.files[_]

    count(file.path) > 1

    dir_path := array.slice(file.path, 0, count(file.path) - 2)
    pkg_path := array.slice(file.rego["package"].path, 1, count(file.rego["package"].path) - 1)

    some i
    count({ i | dir_path[i] != pkg_path[i] }) > 0
    msg := sprintf("%s: package path and directory path is not matched", [concat("/", file.path)])
}
```

もうひとつは「ディレクトリ名とパッケージ名が一致しているか」を確認するポリシーです。こちらはやや複雑なので順番に解説します。

```rego
fail[msg] {
```

まず定番ではありますが、この `regolint` もその他のOPA連携ツールと同じく、ポリシーに違反していたらなんらかの変数（今回は `fail` ）に値を入れるという方法をとっています。

```rego
file := input.files[_]
```

次は `input.files` という配列に入っているファイルの構造データを取り出して `file` に移します。これをやらずに直接 `input.files[x]` を操作もできますが、可読性・デバッグのしやすさの観点から別の変数に移しています。

```rego
count(file.path) > 1
```

これは最初のポリシーで違反判定済みのRegoファイルについては検証しないようにするための条件です。（最初のポリシーが `count(file.path) <= 1` なので同時には成立しない）この後のポリシーが正しくチェックされない可能性を考慮して、安全のために弾くようにしています。

```rego
dir_path := array.slice(file.path, 0, count(file.path) - 2)
pkg_path := array.slice(file.rego["package"].path, 1, count(file.rego["package"].path) - 1)
```

ぱっと見なにをしているのかわかりにくいですが、1行目がファイルパスの配列からファイル名を抜いてディレクトリ名だけにする操作、2行目がパッケージ名（正確にはvirtual document名）の頭に入っている `data` という語を抜いて純粋なパッケージ名にする、という作業です。例として以下のような結果が期待されます。

- 1行目: `["policy", "terraform", "some_policy.rego"]` → `["policy", "terraform"]`
- 2行目: `["data", "policy", "terraform"]` → `["policy", "terraform"]`

`array.slice` を使って、配列の最後と冒頭をそれぞれ削っています。

```rego
some i
count({ i | dir_path[i] != pkg_path[i] }) > 0
```

ということでここが判定の本命です。それぞれ整形された配列に対して **一致していない** 要素がいくつあるかカウントします。もし1つでも一致していなければこのルールが成立し、次の行でエラーの情報が返されます。

```rego
msg := sprintf("%s: package path and directory path is not matched", [concat("/", file.path)])
```

ということでここまでたどり着いたRegoファイルは「ポリシー違反」と判定され、違反の詳細が `msg` に格納され、その後 `fail[msg]` に格納されます。

# まとめ

OPA/Regoがまだ鋭意開発が続いている状態なので、思いついた発想を形にしてみた[^related]回でした。若干ネタ感はありますが、OPAサーバへの認可制御をRegoで表現させようとしているプロダクトなので、こういうアプローチもありなんじゃないかな、と思います。

[^equality]: `=`, `:=`, `==` の違いについては[FAQ](https://www.openpolicyagent.org/docs/latest/faq/#which-equality-operator-should-i-use)をご参照ください
[^issue]: とはいえ本家のコマンドに導入されていたほうが健全かと思うので、これは後日本家にissueをたてて議論したいと考えています。今は時間がない！！
[^related]: 一応探したら同じ発想をした人がいました https://blog.styra.com/blog/linting-rego-with-rego