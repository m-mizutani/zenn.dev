---
title: "Go公式の構造化ロガー（予定）のslogで秘匿値をログから削除する"
emoji: "🚫"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go"]
published: true
---

Go言語ではながらく公式のログ出力に`log`パッケージが使われてきました。しかし昨今のクラウド環境などでのロギングでは構造化ログがほぼ必須であり、そのような流れを受けて公式の構造化ログパッケージ slog が提案されています。2023年8月にリリース見込みの Go 1.21 の[リリースノート](https://go.dev/blog/go1.21rc)にはすでに掲載されており、1.21 で正式に公式に取り込まれるのはほぼ確実かと考えられます。

https://zenn.dev/mizutani/articles/golang-exp-slog

# 背景：絶対にログに秘匿値を出力したくない

オンラインサービスで出力されるログは様々な目的で利用されます。例えば、サービスの運用監視のためにログを集約してアラートを発生させたり、サービスの改善のためにログを集約して分析したり、サービスのセキュリティ監視のためにログを集約して不正アクセスを検知したり、などなど。また、ログは監査に利用されることもあり、原則として保管期間中は削除しない、できないということが前提として様々なログ関連の仕組みが構築されています。

ログに出力される情報が豊富なほど、利用の幅も広がります。特にデバッグやトラブル対応では手がかりが多いほど有利です。しかし、サービスが扱うデータには迂闊に出力してはいけないような情報が含まれることもあります。例えば、パスワードやトークンのような認証情報、氏名、電話番号、住所のような個人情報、そして銀行口座情報やクレジットカード番号などです。この記事では便宜上これらを「秘匿値」と呼ぶことにします。

前述した通りログは一定期間保管し、さらに保管期間中は削除できないようになっていることが多いです。そのため、ログに秘匿情報が出力されてしまうと、その削除には多大な労力が必要になってしまいます。あるいはアクセスできる人を限定するなどの対策を講じる必要がありますが、それによって利用できる場面が少なくなってしまい、ログを活用できなくなってしまいます。

「そもそも秘匿値をログに出すべきではない」というのは至極ごもっともですが、例えば構造体をログに出力する場合、その構造体のフィールドや、さらにネストされた構造体の中に秘匿値が含まれている場合も考えられます。ログに出力する値を選択する際に注意したとしても、構造体自体があとから変更され秘匿値を含むフィールドが追加されるかもしれません。そのようなケースを網羅するのは非常に困難です。一方でなるべく多くの情報をログに残したい、という要求を考えると「構造体をログに出力しない」というのはあまり現実的なアプローチではありません。

# `slog.LogValuer`

slog には `LogValuer` というインターフェースが用意されており、これを実装することでログに出力する値をカスタマイズできます。これを利用して、例えば秘匿値を隠したり、値をマスクしたりすることができます。

```go
type Token string

func (Token) LogValue() slog.Value {
	return slog.StringValue("REDACTED_TOKEN")
}

func main() {
	t := Token("ThisIsSecretToken")
	slog.Info("permission granted", "token", t)
}
```

このコードを実行すると、 `ThisIsSecretToken` という値は出力されず、代わりに `REDACTED_TOKEN` に置き換えられます。

```bash
time=2009-11-10T23:00:00.000Z level=INFO msg=Access token=REDACTED_TOKEN
```

この仕組みは前述した課題を解決するために良さそうに思えますが、構造体に含まれるフィールドには適用されない、という問題があります。例えば、以下のような例では `LogValuer` が機能しません。

```go
type Token string

func (Token) LogValue() slog.Value {
	return slog.StringValue("REDACTED_TOKEN")
}

type AccessLog struct {
	User  string
	Token Token
}

func main() {
	l := AccessLog{
		User:  "mizutani",
		Token: "ThisIsSecretToken",
	}
	slog.Info("Access", "log", l)
}
```

以下のように、隠そうとしていた値がそのまま出力されてしまいます。

```bash
time=2009-11-10T23:00:00.000Z level=INFO msg=Access log="{User:mizutani Token:ThisIsSecretToken}"
```

ということでより厳密に秘匿値を隠すためには、別のアプローチが必要になります。

# `ReplaceAttr` を使う

slog が提供している `TextHandler`, `JSONHandler` には `ReplaceAttr` というオプションがあります。これは属性値として渡された値を出力する前にcallbackを呼び出し、値の差し替えができます。

```go
type Token string

type AccessLog struct {
	User  string
	Token Token
}

func redact(_ []string, a slog.Attr) slog.Attr {
	l, ok := a.Value.Any().(AccessLog)
	if !ok {
		return a
	}
	return slog.Any(a.Key, AccessLog{
		User:  l.User,
		Token: "REDACTED_TOKEN",
	})
}

func main() {
	l := AccessLog{
		User:  "mizutani",
		Token: "ThisIsSecretToken",
	}

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{ReplaceAttr: redact}))
	logger.Info("Access", "log", l)
}
```

このように記述することで、秘匿値を隠すことができます。

```bash
time=2009-11-10T23:00:00.000Z level=INFO msg=Access log="{User:mizutani Token:REDACTED_TOKEN}"
```

しかし、こんな判定ロジックを書くのは全く現実的ではありません。そこでもう少し汎用的に隠蔽できるような仕組みが必要になります。

# masq

前置きが長くなりましたが、このログの秘匿値隠蔽を汎用的にできるようにしたのが以下のパッケージです。

https://github.com/m-mizutani/masq

`masq` は `ReplaceAttr` の callback を生成するためのパッケージです。例えば `EmailAddr` という型の値を隠蔽したい場合、以下のように記述します。

```go
u := struct {
    ID    string
    Email EmailAddr
}{
    ID:    "u123",
    Email: "mizutani@hey.com",
}

logger := slog.New(slog.HandlerOptions{
    ReplaceAttr: masq.New(masq.WithType[EmailAddr]()),
}.NewJSONHandler(os.Stdout))

logger.Info("hello", slog.Any("user", u))
```

これによって以下のように出力されます（jq コマンドで整形しています）。

```json
{
  "time": "2022-12-25T09:00:00.123456789",
  "level": "INFO",
  "msg": "hello",
  "user": {
    "ID": "u123",
    "Email": "[REDACTED]" // ← 隠蔽された
  }
}
```

このように構造体のフィールドの中にあっても、その型に一致する値を隠蔽することができます。

`masq.New` は様々なオプションが利用でき、指定されたオプションに基づいた `ReplaceAttr` 用の callback を生成します。以下のようなオプションが利用できます。

- `WithType[T]()`: 型 `T` に一致する値を隠蔽します
- `WithString(s string)`: 文字列 `s` に一致する値を隠蔽します
- `WithRegex(re regexp.Regex)`: `r 正規表現 `re` に一致する値を隠蔽します
- `WithTag(tag string)`: 構造体の `masq` フィールドタグに一致する値を隠蔽します。例えば `secret` と指定すると `masq:"secret"` というタグが付いたフィールドを隠蔽するようになっています
- `WithFieldName(name string)`: 構造体のフィールド名 `name` に一致する値を隠蔽します
- `WithFieldPrefix(prefix string)`: 構造体のフィールド名 `prefix` で始まる値を隠蔽します

これらは以下のように、複数組み合わせることもできます。

```go
logger := slog.New(slog.HandlerOptions{
    ReplaceAttr: masq.New(
        // AccessToken という型を隠蔽する
        masq.WithType[AccessToken](),

        // 14桁以上16桁以下の数字で始まる文字列を隠蔽する
        masq.WithRegex(regexp.MustCompile(`^\+[1-9]\d{14,16}$`)),

        // masq:"secret" というタグが付いたフィールドを隠蔽する
        masq.WithTag("secret"),

        // Secret というフィールド名をprefixに持つフィールドを隠蔽する
        masq.WithFieldPrefix("Secret"),
    ),
}.NewJSONHandler(out))
```

詳しい使い方については [README](https://github.com/m-mizutani/masq/blob/main/README.md) をご覧ください。

# まとめ

実はこの仕組みは以前から [zlog](https://github.com/m-mizutani/zlog) というパッケージで提供していました。しかし slog がようやく実用段階になったということで、slog に合わせて新たなパッケージとして masq を実装したという経緯です。

先述した通り、slog には `LogValuer` という仕組みもあるので、それを利用するというのも選択肢としてはあると思います。ユースケースに合わせて適切な選択をするのがよく、その選択肢の一つに masq を入れていただければ幸いです。
