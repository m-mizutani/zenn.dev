---
title: "Go公式の構造化ロガー（予定）のslogの出力を見やすくしてみる"
emoji: "🔖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "log"]
published: false
---

Go言語ではながらく公式のログ出力に`log`パッケージが使われてきました。しかし昨今のクラウド環境などでのロギングでは構造化ログがほぼ必須であり、そのような流れを受けて公式の構造化ログパッケージ slog が提案されています。

https://zenn.dev/mizutani/articles/golang-exp-slog

この記事執筆時点で slog は正式に公式に取り込まれたわけではないですが、 1.21 の[マイルストーン](https://github.com/golang/go/milestone/279)にはリストされており、それなりの確度で導入されると思われます。これを受けて自分が開発しているプロダクトでも徐々に slog の導入を進めています。

構造化ロギングのインターフェースが公式で定義されているのは良いことですし、JSONで出力する上でslogの利用は現状特に困ったことはありません。しかし同僚と slog の利用について話していたとき「開発時、コンソールに出力されるログが見づらい」という指摘がありました。確かに言われてみると（近代的なロガーと比べて）見づらいというのも頷けます。

![](https://storage.googleapis.com/zenn-user-upload/c5254856238e-20230611.png)

ということで slog の勉強も兼ねていい感じにログを整形して出力するハンドラを作ってみました。さらに同僚と話をしてみたところ、このあたりのコンソールのログ出力は結構人によって好みが分かれるようなので、だったら可能な限り出力方法を各々の好みにあわせられるようにカスタマイズ性を重視した設計[^1]になっています

https://github.com/m-mizutani/clog

## 使い方

```go
	handler := clog.New(
		clog.WithColor(true),
		clog.WithSource(true),
	)
	logger := slog.New(handler)

	logger.Info("hello, world!", slog.String("foo", "bar"))
	logger.Warn("What?", slog.Group("group1", slog.String("foo", "bar")))
	logger.WithGroup("hex").Error("Ouch!", slog.Int("num", 123))
```

こんな感じで指定すると、以下のように出力されます。

![](https://storage.googleapis.com/zenn-user-upload/9dc1ec381b34-20230611.png)

この他にもAttr（ログの属性値）の整形・出力をカスタマイズするための `WithAttrPrinter` オプションや、ログのフォーマットを `text/template` で指定する `WithTemplate` オプションなどがあります。

```go
	user := User{
		Name:  "mizutani",
		Email: "mizutani@hey.com",
	}

	store := Store{
		Name:    "Jiro",
		Address: "Tokyo",
		Phone:   "123-456-7890",
	}
	group := slog.Group("info", slog.Any("user", user), slog.Any("store", store))

	linearHandler := clog.New(clog.WithPrinter(clog.LinearPrinter))
	slog.New(linearHandler).Info("by LinearPrinter", group)

	prettyHandler := clog.New(clog.WithPrinter(clog.PrettyPrinter))
	slog.New(prettyHandler).Info("by PrettyPrinter", group)

	indentHandler := clog.New(clog.WithPrinter(clog.IndentPrinter))
	slog.New(indentHandler).Info("by IndentHandler", group)
```

![](https://storage.googleapis.com/zenn-user-upload/8501bc645d76-20230611.png)

```go
	tmpl, err := template.New("sample").Parse(`{{.Elapsed | printf "%8.3fs" }} {{.Level}} 📣 📣 📣 <<< "{{.Message}}" 🗒️ `)
	if err != nil {
		panic(err)
	}

	handler := clog.New(
		clog.WithColor(true),
		clog.WithSource(true),
		clog.WithTemplate(tmpl),
	)
	slog.New(handler).Info("hello, world!", slog.String("foo", "bar"))
```

![](https://storage.googleapis.com/zenn-user-upload/91220256a1c8-20230611.png)

## オプション

今のところ実装しているオプションです。

- `WithWriter`: 出力先の `io.Writer` の指定
- `WithLevel`: ログレベルの設定。値は slog の `Level` と同じ。デフォルトは `slog.LevelInfo`。
- `WithTimeFmt`: 時刻フォーマットの指定
- `WithColor`: 色付き、色なしの設定
- `WithColorMap`: 色の指定。 [fatih/color](https://github.com/fatih/color) を利用しているので、色の指定方法はそちらを参照。
- `WithSource`: ソースコードのファイルや行番号の出力の有無
- `WithReplaceAttr`: Attr（ログの属性値）の値の置き換え。 slog の [ReplaceAttr](https://pkg.go.dev/golang.org/x/exp/slog#HandlerOptions) と同じ。
- `WithTemplate`: `text/template` を使ってログのフォーマットを指定
- `WithAttrPrinter`: Attr（ログの属性値）を整形・出力するための

# Handlerの書き方（興味ある人向け）

slogはログの出力を `Handler` というインターフェースで抽象化しています。標準では `TextHandler` および `JSONHandler` が提供されていますが、自分で独自の `Handler` を実装することもできます。

Handlerのインターフェースには以下のメソッドが必要です。（詳しくは[公式ドキュメント](https://pkg.go.dev/golang.org/x/exp/slog#Handler)を参照）

- `Enabled(context.Context, Level) bool`: 指定されたログレベルを出力するかどうかを判定します。これは早めにロギング処理をするかどうか判断することでパフォーマンスを向上させます。
- `Handle(context.Context, Record) error`: 実際のロギング処理を記述するメソッドです。ログの出力先やフォーマットなどはこのメソッド内で実装します。
- `WithAttrs` と `WithGroups`: これらはログの属性値やグループを追加するためのものです。これらを実装することで、ログの属性値やグループを追加した `Handler` を作ることができます。



[^1]: その代わりパフォーマンスについてはあまり重要視していません。これは開発時のロギングにフォーカスしており、本番環境のように大量のログをさばくような状況ではないということを前提としています。
