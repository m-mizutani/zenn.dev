---
title: "⚙️ OPAコマンドの利用"
---

まずは `opa` コマンドについてです。`opa`コマンドはいろいろな機能をサブコマンドで備えていますが、よく使うと思われる部分に絞って紹介したいと思います。

コマンドのインストールについては[公式ドキュメント](https://www.openpolicyagent.org/docs/v0.11.0/get-started/#prerequisites)を参照してください。macOSであれば homebrew からのインストールも可能です。


# run

OPAの実行環境を作るためのコマンドです。大きく分けて 1) CLIでインタラクティブにクエリを打ち込めるシェルを立ち上げる、2) サーバとして起動してHTTPによって操作する2つのモードがあります。

## インタラクティブモード

ポリシーのデバッグをするのに便利なモードです。`./policy` にポリシーファイルがある場合は以下のように起動します。

```shell
$ opa run ./policy
OPA 0.34.2 (commit , built at )

Run 'help' to see a list of commands and check for updates.
>
```

ディレクトリを指定すると再帰的にJSON、YAML、Regoのファイルを探索して読み込みます。また、ここで指定したディレクトリがルートとして扱われます。Regoファイルについてはパッケージ名でパスが決定するのでディレクトリ構造は気にする必要はありませんが、データについてはどこをルートディレクトリになるかでパスが変わってしまうため、注意が必要です。

`input` にデータを渡したい場合、ちょっと特殊ですが `mydata.json` を使うとして以下のように指定します。

```
$ opa run ./policy repl.input:mydata.json
```

さらにデバッグ目的の場合、ファイルを度々変更することになると思われるのでホットリロードを有効化する `-w` オプションを使うのをお勧めします。

```
$ opa run -w ./policy repl.input:mydata.json
```

インタラクティブモードではとりあえず `data` と打つことで読み込まれたデータおよびポリシーが一覧できます。

```
> data
{
  "example": {
    "allow": true,
    "roles": [
      "admin",
      "developer"
    ]
  },
  "repl": {
    "input": {
      "user": "blue"
    }
  }
}
```

必要に応じて絞り込みができます。

```
> data.example
{
  "allow": true,
  "roles": [
    "admin",
    "developer"
  ]
}
> data.example.roles
[
  "admin",
  "developer"
]
```

結果が2つ以上になる場合、結果の組み合わせを表形式で出力してくれます。

```
> data.example.roles[x]
+---+-----------------------+
| x | data.example.roles[x] |
+---+-----------------------+
| 0 | "admin"               |
| 1 | "developer"           |
+---+-----------------------+
```

## サーバモード

サーバとして使う場合は `-s` オプションを付与します。

```
$ opa run -s
{"addrs":[":8181"],"diagnostic-addrs":[],"level":"info","msg":"Initializing server.","time":"2021-12-11T17:38:10+09:00"}
```

デフォルトだと `:8181` でHTTPサーバを立ち上げるため、以下のコマンドでアクセスできます。

```bash
% curl http://localhost:8181/v1/data | jq
*   Trying ::1:8181...
* Connected to localhost (::1) port 8181 (#0)
> GET /v1/data HTTP/1.1
> Host: localhost:8181
> User-Agent: curl/7.77.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Content-Type: application/json
< Date: Sat, 11 Dec 2021 08:40:58 GMT
< Content-Length: 54
<
* Connection #0 to host localhost left intact
{
  "result": {
    "example": {
      "roles": [
        "admin",
        "developer"
      ]
    }
  }
}
```

`/v1/data` が `data` と同様の意味をもちます。例えば `/v1/data/example` とすることで、 `data.example` と同様の結果を得ることができます。

```bash
$ curl http://localhost:8181/v1/data/example | jq
{
  "result": {
    "roles": [
      "admin",
      "developer"
    ]
  }
}
```

`input` を渡したい場合は `POST` メソッドでデータを送信します。

```bash
$ curl -X POST http://localhost:8181/v1/data/example -d '{"input":{"user":"blue"}}' | jq
{
  "result": {
    "allow": true,
    "roles": [
      "admin",
      "developer"
    ]
  }
}
```

基本的な動作はインタラクティブモードと同じですが、サーバに`input`のデータを渡す際は `{"input": ... }` の形式する必要があり、一方サーバからの結果は `{"result": ... }` の形式になっているという点に注意が必要です。`input`の中身だけ渡して期待した動きをしない、というハマり方が多いようです。

この他、APIの詳細については[公式ドキュメント](https://www.openpolicyagent.org/docs/latest/integration/#integrating-with-the-rest-api)を参照してください。サーバの運用事例については、後日別の記事で紹介します。

# eval

CLIでポリシーを評価したいときに利用するサブコマンドです。例えばGitHub ActionのCIでなんらかのスキャン結果を出力した後、その結果に基づいてCIを成功・あるいは失敗させるといった判定をするといったユースケースが想定[^judge]されます。

```bash
$ opa eval -b ./rego/example/ data
{
  "result": [
    {
      "expressions": [
        {
          "value": {
            "example": {
              "roles": [
                "admin",
                "developer"
              ]
            }
          },
          "text": "data",
          "location": {
            "row": 1,
            "col": 1
          }
        }
      ]
    }
  ]
}
```

`eval` の場合はデフォルトで出力形式がJSONになっており、かつ結果が式（ `expressions` ）と割り当てられた変数（ `bindings` ）に分裂します。コマンドの最後の引数がクエリになっており、変数の割当をすると、`bindings`の方に値が出力されます。

```bash
$ opa eval -b ./rego/example/ 'x := data'
{
  "result": [
    {
      "expressions": [
        {
          "value": true,
          "text": "x := data",
          "location": {
            "row": 1,
            "col": 1
          }
        }
      ],
      "bindings": {
        "x": {
          "example": {
            "roles": [
              "admin",
              "developer"
            ]
          }
        }
      }
    }
  ]
}
```

解釈が煩わしいので `run` のときと同じ形式で見たい、という場合は `-f pretty` を利用することをお勧めします。

```bash
$ opa eval -f pretty -b ./rego/example/ 'x := data'
+---------------------------------------------+
|                      x                      |
+---------------------------------------------+
| {"example":{"roles":["admin","developer"]}} |
+---------------------------------------------+
```

その他、よく使いそうなオプションをいくつか紹介します。

- `--fail`: クエリの結果が結果が空、あるいは未定義だった場合にプロセスを非ゼロ値で異常終了させます
- `--fail-defined`: `--fail` とは逆で、クエリの結果が定義済みだった場合にプロセスを異常終了させます。OPAでは「問題を発見したらメッセージを返す」というポリシーの書き方がよく見られ、その使い方だとこちらのオプションが便利です
- `--input`: `input`に使うJSONファイルを指定します。
- `--stdin-input`: `input`に使うデータを標準入力から受け取れます。

[^judge]: もちろんシェルスクリプトを含む他のプログラミング言語で判定の処理をするという選択肢もあります。