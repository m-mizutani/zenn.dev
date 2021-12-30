---
title: "デバッグ"
---

Regoは宣言型の記述言語であり、近年メジャーな手続き型言語と考え方がいささか異なります。そのためどのように動作するかを慎重に確認しながらポリシーを書くという状況が多くなりがちです。筆者もまだRegoを書き始めて日が浅いのですが、今回の記事ではデバッグに使える機能である `trace` と `print` について紹介したいと思います。

# trace

もともとRegoでは組み込みの `trace` 関数をつかって、どのように評価がされたのかを検証するというデバッグ方法がありました。具体的な使用例を以下に示します。

```rego
package debugging

servers := [
    {
        "name": "blue",
        "addr": "10.0.1.2",
        "port": [21, 22, 80],
    },
    {
        "name": "orange",
        "addr": "10.0.1.3",
        "port": [22, 5432],
    },
]

trace_example {
    server := servers[x]
    trace(sprintf("index:%d", [x]))

    is_ssh_port(server.port[_])
    is_orange(server.name)
}

is_ssh_port(p) {
    trace(sprintf("port=%d", [p]))
    p == 22
}

is_orange(n) {
    trace(sprintf("name=%s", [n]))
    n == "orange"
}
```

このポリシーに対して、以下のようにコマンドを実行すると結果が表示されます。

```bash
$ opa eval --explain=notes --format=pretty -b . data
query:1           Enter data = _
debug.rego:16     | Enter data.debugging.trace_example
debug.rego:18     | | Note "index:0"
debug.rego:24     | | Enter data.debugging.is_ssh_port
debug.rego:28     | | | Enter data.debugging.is_ssh_port2
debug.rego:29     | | | | Note "port=22"
debug.rego:18     | | Note "index:1"
debug.rego:33     | | Enter data.debugging.is_orange
debug.rego:34     | | | Note "name=orange"

(以下割愛)
```

順番に確認していきましょう。まず最初の

```bash
query:1           Enter data = _
```

はクエリから呼び出された `data` を示しています。これを呼び出すことでbasic/virtual documentがそれぞれ評価されます。

```bash
debug.rego:16     | Enter data.debugging.trace_example
debug.rego:18     | | Note "index:0"
```

まず最初のイテレーションです。 `trace(sprintf("index:%d", [x]))` とすることで `servers` 配列のどの要素を検査しているのかを確認できます。ここでは最初の

```rego
    {
        "name": "blue",
        "addr": "10.0.1.2",
        "port": [21, 22, 80],
    },
```

を検査していることになります。次に、

```bash
debug.rego:24     | | Enter data.debugging.is_ssh_port
debug.rego:28     | | | Enter data.debugging.is_ssh_port2
debug.rego:29     | | | | Note "port=22"
```

となっており、 `is_ssh_port` のルールに突入していることがわかります。 `is_ssh_port` 内では `trace(sprintf("port=%d", [p]))` という命令によってマッチしたポート番号が表示されます。

ここで注意するべき点として、`trace` 関数は **そのルール内の条件がすべて成立したときだけしか発火しません**。そのため、`22` より前に検査されているであろう `21` がここには表示されていません。これは次の行にも現れており、 `is_ssh_port` を突破したはずの1つ目の要素では `is_orange` のチェックをうけていないように見えますが、これも `is_orange` の結果が偽になるため表示されていない、というわけです。

一方、2番目の要素は

```bash
debug.rego:18     | | Note "index:1"
debug.rego:33     | | Enter data.debugging.is_orange
debug.rego:34     | | | Note "name=orange"
```

となっており、 `is_orange` が確認されて、最終的な結果が `true` になっています。

# print

このように `trace` 関数を使うことで、一通りの流れや要所での変数の値を確認するという機能は実現できるのですが、実用上いくらか課題があったようでした。

- 値が出力されるのがルールが成立したときのみであり、直感に反する
- `trace` は単一の文字列型しか受け付けておらず、例えば変数を確認したい場合は `sprintf` 関数を使わねばならず煩わしい。`sprintf`も多言語と若干フォーマットが異なる（引数が文字列＋配列）のもよく間違える[^author]
- `trace` の結果を見るためには `--explain=notes` というオプションを付ける必要がある（CLI）が、初学者だとこれを把握しづらい


そのような背景から[^issue] [v0.34.0](https://github.com/open-policy-agent/opa/releases/tag/v0.34.0)[^print]から新たに `print` 関数が導入されました。`print`関数はよりシンプルにデバッグメッセージを記述できるようになっています。以下は先程のルールの部分を `print` で書き直したものです。

```rego
trace_example {
    server := servers[x]
    print("index:", x)

    is_ssh_port(server.port[_])
    is_orange(server.name)
}

is_ssh_port(p) {
    print("port=", p)
    p == 22
}

is_orange(n) {
    print("name=", n)
    n == "orange"
}
```

`print` は任意個の引数を受付け、なおかつ変数の型を気にせずよしなに表示してくれるためシンプルに記述できるようになりました。また、出力のタイミングもtraceとは異なります。

```
% opa eval -b . data
index: 0
port= 21
port= 22
name= blue
port= 80
index: 1
name= orange
port= 5432

(以下割愛)
```

ルールが成立したときだけではなく、`print` 関数に差し掛かったタイミングで値がすべて[^cache]出力されるようになっています。これで「どの値が投入されたか？」という調査を直感的にできるようになりました。

# traceとprintの使い分け

似たような `trace` と `print` という2つの機能ですが、いくらか差分はあり状況によって使い分けられると考えています。筆者が現状で考える棲み分けは以下のとおりです。

- `print` **デバッグ時のみ使い、デバッグが終わったら消す**：記述が非常に容易になっている点から、デバッグ作業時にスッと差し込んで値を確認する目的が良いと考えられます。一方、`print`はオプションなどで出力の制御ができず常に出力され続けます。本番環境などで不必要にログを吐き出すことになってしまうため、そのユースケースでは `trace` の方が適切だと考えます
- `trace` **本番環境などで一時的にログを出力したい備えとして使う**: `trace` は `--explain` オプションで指定しないと出力されないため、必要に応じて出力を制御することができます。本番環境などで一時的にログを出力したいなどの状況で便利です。また、出力内容も `print` に比べ、どのルール内で評価されたかなどの情報も併せて出力されるため、実行環境に触れないような状況のログをとるのに適しています。

# まとめ

OPA/Regoはまだ進化中であり、デバッグなどのエコシステムが十全に整っている状況かと言うとまだ発展の余地はあるかもしれません。だからこそ実際に利用し、改善に貢献していけるといいのではないかなというように個人的に考えています。

[^issue]: `print` 関数導入に関する議論は https://github.com/open-policy-agent/opa/issues/3319 にあります
[^author]: これは筆者の感想です
[^print]: リリースが2021年10月末なので本当に最近使えるようになった機能のようです。
[^cache]: 2つ目の要素の `22` も表示されるように思えるのですが、OPAは一度 `true` などの値を返した関数やルール＋値の組み合わせをキャッシュして再度呼ばないようにしているようです。これは同じ結果を再度計算しないで計算コストを下げるメモ化再帰的な戦略をとっているものと思われます。
