---
title: "Go公式の構造化ロガー（として提案されている）slogを触ってみたメモ"
emoji: "📝"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "log"]
published: true
---

Go言語ではながらく公式のロガーとして [log](https://pkg.go.dev/log) パッケージがありました。これは非常にシンプルなもので構造データをうまく表現できなかったりログレベルを分けるということができません。CLIで使うシンプルなインタラクションであればこれで十分なのですが、クラウド上のバックエンドで動かすサービスにとっては構造化ロギングやログレベルの出し分けは事実上必須であり、そのための機能は十分と言えませんでした。

これに対して様々なロガーが3rd party packageとして公開されてきましたが、一方で公式に導入されようとしているロガーもあります。それが[slog](https://pkg.go.dev/golang.org/x/exp/slog)です。まだ提案の段階ではありますが、現状で使える実装を触ってみたところかなり実用的な段階だなと感じたので、自分用の備忘録を兼ねてメモを残してみます。

サンプルコードはここにも置いてあります。
https://github.com/m-mizutani/slog-examples

:::message alert
slogは現状まだ提案段階[^proposal]であり、proposalされている[issue](https://github.com/golang/go/issues/56345)をみても引き続き活発に議論されています。記事を参考にして頂く場合、内容は執筆時点のものである点に注意してください。
:::

# 基本的な使い方

まず基本的な使い方を見てみます。ログ出力用に `Info`, `Debug` などレベルごとのメソッドが用意されており、第一引数にログメッセージを、第2引数以降はキーと値を交互に入れます。

```go
	slog.Info("hello world!", "name", "blue", "No", 5)
```

これによってロガーがキーと値を構造情報とみなしてくれます。デフォルトだとテキスト形式なので、以下の様な出力になります。

```
2022/11/23 09:53:27 INFO hello world! name=blue No=5
```

# JSON形式でログを出力する

JSON形式で出力するためのロガーを別途作成します。`os.Stdout` で出力先を標準出力に指定しています。

```go
logger := slog.New(slog.NewJSONHandler(os.Stdout))
logger.Info("hello structured log", "name", "blue", "No", 5)
```

これによって以下のように出力されます（以下を含め、出力結果はjqでフォーマット済み）

```json
{
  "time": "2022-11-23T09:58:03.153178+09:00",
  "level": "INFO",
  "msg": "hello structured log",
  "name": "blue",
  "No": 5
}
```

# ログにキーと値を埋め込む

キーと値を埋め込む方法は様々な方法が提供されています。

最初の例では引数にキーと値を交互に指定していましたが、これは順番を間違えると意図したログが表示されなくなります。これを防ぎたい場合は型を指定するメソッドを利用できます。

```go
logger.Info("hello",
    slog.Bool("allowed", true),
    slog.String("name", "blue"),
)
```

```json
{
  "time": "2022-11-23T09:58:03.15275+09:00",
  "level": "INFO",
  "msg": "hello",
  "allowed": true,
  "name": "blue"
}
```

混在すると間違いやすくなるためあまり推奨はでき無さそうですが、キーと値を交互に入れつつ型指定のメソッドも混ぜることはできます。

```go
logger.Info("hello",
    slog.Bool("allowed", true),
    slog.String("name", "blue"),
    "version", 3.2,
)
```

```json
{
  "time": "2022-11-23T09:58:03.153003+09:00",
  "level": "INFO",
  "msg": "hello",
  "allowed": true,
  "name": "blue",
  "version": 3.2
}
```

構造体の中身もJSON化してくれ、ネストもされた構造体も同様に処理してくれます。

```go
data := struct {
    Color  string
    Nested struct {
        Depth int
    }
}{
    Color: "blue",
    Nested: struct{ Depth int }{
        Depth: 1,
    },
}

logger.Info("hello", slog.Any("data", data))
```

```json
{
  "time": "2022-11-23T09:58:03.153035+09:00",
  "level": "INFO",
  "msg": "hello",
  "data": {
    "Color": "blue",
    "Nested": {
      "Depth": 1
    }
  }
}
```

ネストさせるときわざわざ構造体を定義したくない、という場合は `slog.Group` を使うことでネスト構造を作ることができます。

```go
logger.Info("hello",
    slog.Group("group1",
        slog.String("color", "blue"),
    ),
    slog.Group("group2",
        slog.String("version", "v3.2.0"),
    ),
)
```

```json
{
  "time": "2022-11-23T09:58:03.153113+09:00",
  "level": "INFO",
  "msg": "hello",
  "group1": {
    "color": "blue"
  },
  "group2": {
    "version": "v3.2.0"
  }
}
```

# 出力されるログレベルを設定する

ログレベルは `HandlerOptions` を使って指定できます。ちなみに記事執筆時点でログレベルは

- `Debug`
- `Info`
- `Warn`
- `Error`

の4段階になっています。

```go
logger := slog.New(slog.HandlerOptions{
    Level: slog.WarnLevel,
}.NewJSONHandler(os.Stdout))

logger.Debug("no output") // 出力されない
logger.Info("no output") // 出力されない
logger.Warn("WARNING") // 出力される
logger.Error("ERROR", errors.New("my error")) // 出力される
```

```json
{"time":"2022-11-23T09:58:03.153224+09:00","level":"WARN","msg":"WARNING"}
{"time":"2022-11-23T09:58:03.153228+09:00","level":"ERROR","msg":"ERROR","err":"my error"}
```

# その他の便利機能

## ログを出力したソースコードの場所をログに含める

`AddSource` というオプションを有効化することでファイル名および行数をログに含めてくれます。

```go
logger := slog.New(slog.HandlerOptions{
    AddSource: true,
}.NewJSONHandler(os.Stdout))
logger.Info("hello")
```

```json
{
  "time": "2022-11-23T09:58:03.153214+09:00",
  "level": "INFO",
  "source": "/Users/mizutani/.ghq/github.com/m-mizutani/slog-examples/handler_option_test.go:15",
  "msg": "hello"
}
```

## 埋め込んだキーと値を引き継ぐ

`With` メソッドを使うことでキーと値を埋め込んだ新たなロガーを作成できます。例えば同じリクエストを処理したログを検索したいとなった場合に一意なリクエストIDを埋め込んだり、そのリクエストのメタ情報を埋め込んでおくことでデバッグなどが容易になります。

```go
logger := slog.New(slog.NewJSONHandler(os.Stdout))
logger2 := logger.With(
    slog.String("method", "GET"),
    slog.String("path", "/v1/api/hello"),
)

logger2.Info("hello")
```

```json
{
  "time": "2022-11-23T09:58:03.153201+09:00",
  "level": "INFO",
  "msg": "hello",
  "method": "GET",
  "path": "/v1/api/hello"
}
```

## 出力される値のフォーマットを書き換える

`LogValue() slog.Value` というインターフェースを持つ型を用意することで、値が出力される際のフォーマットなどを任意にいじることができます。これは `String() string` インターフェースを持っていると `fmt.Println` が整形してくれるのと似たような機能です。

```go
type upperCase string

func (x upperCase) LogValue() slog.Value {
	return slog.StringValue(strings.ToUpper(string(x)))
}
```

```go
var s upperCase = "is it small?"
logger := slog.New(slog.NewJSONHandler(os.Stdout))
logger.Info("hello", "s", s)
```

```json
{
  "time": "2022-11-23T09:58:03.15326+09:00",
  "level": "INFO",
  "msg": "hello",
  "s": "IS IT SMALL?"
}
```

様々な用途に使えそうですが、現状では構造体の中の値についてまでは検査してくれないので、秘匿値のフィルタなどの用途ではまだ不十分そうです。

## 出力される値を検査して書き換える

`HandlerOptions` で `ReplaceAttr` というフィールドを指定することで、設定されたキーと値を検査して出力前に内容を置き換えるなどの処理ができます。

```go
logger := slog.New(slog.HandlerOptions{
    ReplaceAttr: func(a slog.Attr) slog.Attr {
        if a.Key == "color" { // colorというキーがきたら orange という値に書き換える
            return slog.String("color", "orange")
        }
        return a
    },
}.NewJSONHandler(os.Stdout))

logger.Info("hello",
    slog.String("region", "asia"),
    slog.String("color", "blue"),
)
```

```json
{
  "time": "2022-11-23T09:58:03.153235+09:00",
  "level": "INFO",
  "msg": "hello",
  "region": "asia",
  "color": "orange" // <- 書き換わっっている
}
```

# まとめ

まだ議論も活発であり仕様も確定していない段階ではありますが、個人的には構造化ロガーとして使うための最低限の機能およびいくつかの便利機能もあり、好感触でした。提案が受け入れられたら、自分の開発するパッケージにも積極的に導入していきたいと考えています。

[^proposal]: ちなみに筆者はGo言語の開発体制や提案のフローなどにそこまで詳しくはないため、何か間違っていたり的はずれなことを言っていたらこっそり教えて下さい。