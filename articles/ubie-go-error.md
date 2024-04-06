---
title: "UbieにおけるGo言語のエラーハンドリング"
emoji: "⛳"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go"]
published: false
publication_name: "ubie_dev"
---

# 背景

Ubieでは以下の記事にあるように、一昨年から新しく始めるプロジェクトにはGoとTypeScriptを積極的に採用しています。私は本来プロダクトセキュリティが主な専門領域なのですが、公私ともに普段からGoでツールやサービスの開発をしているため、社内のGo言語の普及をサポートしたりプロダクト開発に参加したりしています。

https://zenn.dev/ubie_dev/articles/4437cde02a672b

Go言語で開発したことがある方はご存知かと思いますが、Goは標準パッケージで提供されているエラーハンドリングは最低限の機能しか提供されていません。これは、CLIツールなどではエラーの内容が簡潔に表せてよいのですが、サーバサイドアプリケーションのようにエラーにまつわる情報を詳細に残してあとから調査に利用する、という場面では不向きです。特に本番環境でしか再現しないようなエラーの場合は、以下に関連情報を残せているかが、問題の解決に大きく影響します。

先日も[話題](https://methane.hatenablog.jp/entry/2024/04/02/Go%E3%81%AEerror%E3%81%8C%E3%82%B9%E3%82%BF%E3%83%83%E3%82%AF%E3%83%88%E3%83%AC%E3%83%BC%E3%82%B9%E3%82%92%E5%90%AB%E3%81%BE%E3%81%AA%E3%81%84%E7%90%86%E7%94%B1)になっていましたが、Goの標準のエラーハンドリングがシンプルになっているのはポリシーなどによるものではないそうです。そのため、自分たちが必要としている機能を実装して運用してくのが適切ではと考えています。

# Go言語でのエラーハンドリングの要件

サーバサイドアプリケーションでのGoのエラーハンドリングにおいて、以下のような要件があると考えています。

## (1) エラーのスタックトレースを残す

先述したブログにも話題に上がっていたスタックトレースですが、サーバサイドアプリケーションのエラーハンドリングでは必須の機能と考えています。エラーが発生した場所を特定するだけならば一意なエラーメッセージを出力するだけでも可能ですが、どのような経路でエラーが発生したのかを知ることは、エラーの原因を特定する上で非常に重要です。また、エラーメッセージだと直感的にどこでエラーが発生したのかがわかりにくく、スタックトレースの方が有効な場合が多いです。

## (2) エラーの種類と関連情報を分離する

一般的なGoのエラーハンドリングだとエラーメッセージにエラーに関連する情報の値を埋め込む形でエラーを扱うと思います。

```go
fmt.Errorf("failed to open file: %s", fname)
```

しかしこの方法だとエラーの種類を示す情報とエラーに関連する情報が一つの文字列に混ざり合ってしまいます。これによって、例えば、エラーの種類ごとに集計したり集約をしたい場合、エラーメッセージをパースしてエラーの種類を取り出す必要があります。値の埋込かたはエラーによって様々なので、パースの方法もエラーごとに異なり、これが集約や集計をさらに難しくしています。

このことからエラーに関連する情報とエラーの種類を示す情報は分離して扱うべきだと考えています。

## (3) 構造化ログに対応する

クラウド環境におけるロギングサービス（例：AWSのCloudWatch LogsやGoogle CloudのCloud Loggingなど）では構造化ログを扱えるようになっています。これはJSON形式などでログを出力することで、検索や集計を容易にします。

また同時に、Go 1.21 からは標準パッケージに構造化ログをサポートする `slog` パッケージが追加さました。このような背景から、エラーも構造化ログとして出力することで、スタックトレースやエラーの関連情報を扱いやすくなり、様々な恩恵をうけられます。

# エラーハンドリングに利用しているライブラリ `goerr`

https://github.com/m-mizutani/goerr

Ubie内のGoプロジェクトでは、自分が実装した上記のライブラリを利用しています。もともとはよりエラーの情報を詳細に残すために作成したものですが、 `github.com/pkg/errors` がアーカイブされたこともあり、現状ではこのライブラリを活用しています。本番環境で利用されているいくつものサービスで利用されていつつ、最初に実装してから約4年間ほど自分で使い倒してきたライブラリなので、ある程度安定していると言えるかなと考えています。

機能としてはシンプルで、以下のような特徴を持ちます。

- エラーのスタックトレースを残す
- エラーに関連情報を付与し、あとから取り出せる（key + valueの形でデータを付与できる）
- `slog` に対応しており、構造化ログとして出力できる

以下、実際のコードとともに機能を紹介します。

## スタックトレースの記録と表示

まずはエラーのスタックトレースを記録する機能です。 `github.com/pkg/errors` と同様に `Wrap()` 関数を用意しており、これによって異なるエラーをラップしつつ、スタックトレースを記録することができます。

```go
func someAction(fname string) error {
	if _, err := os.Open(fname); err != nil {
		return goerr.Wrap(err, "failed to open file")
	}
	return nil
}

func main() {
	if err := someAction("no_such_file.txt"); err != nil {
		log.Fatalf("%+v", err)
	}
}
```

これを実行すると以下のような出力が得られます。

```
2024/04/06 10:30:27 failed to open file: open no_such_file.txt: no such file or directory
main.someAction
        /Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/stacktrace_print/main.go:12
main.main
        /Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/stacktrace_print/main.go:18
runtime.main
        /usr/local/go/src/runtime/proc.go:271
runtime.goexit
        /usr/local/go/src/runtime/asm_arm64.s:1222
exit status 1
```

この `%+v` の書式は `github.com/pkg/errors` と互換性があるように実装しています。そのため、 Sentry のように  `github.com/pkg/errors` に対応しているサービスの場合はそのまま利用することができます。

![](https://storage.googleapis.com/zenn-user-upload/082973db9f7d-20240406.png)
*Sentryでのスタックトレース表示例*

また、 `goerr.Error` では `Stacks()` というメソッドを用意しており、これを使ってスタックトレースを構造データのまま取り出すことができます。 `goerr.Error` の取得は `goerr.Unwrap()` を使うこともできますし、標準パッケージの `errors.As()` 関数を使うこともできます。

```go
if err := someAction("no_such_file.txt"); err != nil {
  var goErr *goerr.Error
  if errors.As(err, &goErr); goErr != nil {
    for i, st := range goErr.Stacks() {
      log.Printf("%d: %v\n", i, st)
    }
  }
  log.Fatal(err)
}
```

こちらは以下のように出力されます。一般的な運用であればあまり必要ない機能ですが、特殊なデバッグや独自のエラーハンドリング機能などと統合する際に利用することができます。

```
2024/04/06 15:03:54 0: &{Func:main.someAction File:/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/stacktrace_extract/main.go Line:12}
2024/04/06 15:03:54 1: &{Func:main.main File:/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/stacktrace_extract/main.go Line:18}
2024/04/06 15:03:54 2: &{Func:runtime.main File:/usr/local/go/src/runtime/proc.go Line:271}
2024/04/06 15:03:54 3: &{Func:runtime.goexit File:/usr/local/go/src/runtime/asm_arm64.s Line:1222}
2024/04/06 15:03:54 failed to open file: open no_such_file.txt: no such file or directory
exit status 1
```

## エラーに関連情報を付与する

`goerr` は `With(key, value)` というメソッドを使ってエラーに関連情報を付与することができます。

一方で `goerr` の `With` メソッドを使うことでエラーメッセージを変更せずに関連情報を追加することができるため、エラーログの集約が容易になります。また、Sentry などのエラーハンドリングサービスもこの機能を使ってエラーをより正確に扱うことができます。

```go
var errFormatMismatch = errors.New("format mismatch")

func someAction(tasks []task) error {
	for _, t := range tasks {
		if err := validateData(t.Data); err != nil {
			return goerr.Wrap(err, "failed to validate data").With("name", t.Name)
		}
	}
	// ....
	return nil
}

func validateData(data string) error {
	if !strings.HasPrefix(data, "data:") {
		return goerr.Wrap(errFormatMismatch).With("data", data)
	}
	return nil
}

type task struct {
	Name string
	Data string
}

func main() {
	tasks := []task{
		{Name: "task1", Data: "data:1"},
		{Name: "task2", Data: "invalid"},
		{Name: "task3", Data: "data:3"},
	}
	if err := someAction(tasks); err != nil {
		if goErr := goerr.Unwrap(err); goErr != nil {
			for k, v := range goErr.Values() {
				log.Printf("var: %s => %v\n", k, v)
			}
		}
		log.Fatalf("msg: %s", err)
	}
}
```

Output:
```
2024/04/06 14:40:59 var: data => invalid
2024/04/06 14:40:59 var: name => task2
2024/04/06 14:40:59 msg: failed to validate data: : format mismatch
exit status 1
```

例えば Sentry にエラーを送信する場合、`goErr.Values()` で関連情報を取り出してそれをスコープにセットすることで、関連情報を保ったままエラーを送信することができます。

```go
// Sending error to Sentry
hub := sentry.CurrentHub().Clone()
hub.ConfigureScope(func(scope *sentry.Scope) {
  if goErr := goerr.Unwrap(err); goErr != nil {
    for k, v := range goErr.Values() {
      scope.SetExtra(k, v)
    }
  }
})
evID := hub.CaptureException(err)
```

![](https://storage.googleapis.com/zenn-user-upload/548f7f585e38-20240406.png)
*Sentryでの関連情報表示例*

## `slog` による構造化ロギング

先述した通り、`Stacks()` と `Values()` でエラーのスタックトレースと関連情報を取り出すことができます。これを利用して、構造化ログを出力することができますが、プロジェクトごとにエラーを構造化するのは面倒です。そこで、`goerr` は `slog.LogValuer` インターフェースを標準で実装しています。 `slog` と組み合わせて利用することで、エラーを構造化ログとして出力することができます。

これによって、スタックトレースや関連情報を追加実装無しに構造化して出力できます。また、Wrapされたエラーについても再帰的に内容を出力するようにしています。

```go
var errRuntime = errors.New("runtime error")

func someAction(input string) error {
	if err := validate(input); err != nil {
		return goerr.Wrap(err, "failed validation")
	}
	return nil
}

func validate(input string) error {
	if input != "OK" {
		return goerr.Wrap(errRuntime, "invalid input").With("input", input)
	}
	return nil
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := someAction("ng"); err != nil {
		logger.Error("aborted myapp", slog.Any("error", err))
	}
}
```

Output:
```json
{
  "time": "2024-04-06T11:32:40.350873+09:00",
  "level": "ERROR",
  "msg": "aborted myapp",
  "error": {
    "message": "failed validation",
    "stacktrace": [
      "/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/logging/main.go:16 main.someAction",
      "/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/logging/main.go:30 main.main",
      "/usr/local/go/src/runtime/proc.go:271 runtime.main",
      "/usr/local/go/src/runtime/asm_arm64.s:1222 runtime.goexit"
    ],
    "cause": {
      "message": "invalid input",
      "values": {
        "input": "ng"
      },
      "stacktrace": [
        "/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/logging/main.go:23 main.validate",
        "/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/logging/main.go:15 main.someAction",
        "/Users/mizutani/.ghq/github.com/m-mizutani/goerr/examples/logging/main.go:30 main.main",
        "/usr/local/go/src/runtime/proc.go:271 runtime.main",
        "/usr/local/go/src/runtime/asm_arm64.s:1222 runtime.goexit"
      ],
      "cause": "runtime error"
    }
  }
}
```

# おわりに

一言でエラーハンドリングといっても、その要件はプロジェクトやアプリケーションによって異なります。特にサーバサイドアプリケーションのエラーハンドリングはビジネスの問題に直結することもあるため、なるべく容易に対応ができるようにしておくのが望ましいと考えます。

もちろん、他の組織や企業における様々なアプローチもあるかと思いますので、今回の記事が一例として参考になれば幸いです。

# 宣伝

Ubieでは引き続き、Goを中心として開発するエンジニアを募集しています。Go言語での開発経験がある方、または興味がある方はぜひお声がけください。
https://herp.careers/v1/ubiehr/MVrTGYYMgRiy

また、セキュリティ関連のエンジニアリングも主にGo言語を利用しています。こちらも興味がある方はお気軽にお問い合わせください。
https://herp.careers/v1/ubiehr/cQ6vihXLiMLg

