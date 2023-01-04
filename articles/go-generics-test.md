---
title: "Genericsを利用したGoのテストユーティリティ"
emoji: "🧪"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "test"]
published: true
---

# **TL; DR**

GoのGenericsを活用したテストユーティリティを試験的に作ってみました。

https://github.com/m-mizutani/gt

こんな感じにテストを記述できます。

```go
colors := ["red", "blue"]

// NG: colors が配列なのに、文字型と比較しようとしてコンパイルエラーになる
// gt.Array(t, colors).Equal("red")

// NG: 配列同士だが、colorsは []string なのに対して []int を比較しようとしているのでコンパイルエラーになる
// gt.Array(t, colors).Equal([]int{1, 2})

// ↓はOKでコンパイルはできる
gt.Array(t, colors).Equal([]string{"red", "blue"}) // <- Pass
gt.Array(t, colors).Have("orange")                 // <- Fail

```

# **やりたいこと**

Goのテストはもともと公式から [testing](https://pkg.go.dev/testing) パッケージが提供されており、これを利用してテストが記述できます。

```go
resp, err := mypkg.MyFunc()
if err != nil {
	t.Errorf("expected no error, but actual is %v", err)
}
if resp != "ok" {
	t.Errorf("expected 'ok', but actual is '%s', resp)
}

```

この書き方だと数行のテストの場合は特に困らないのですが、検査する項目数が多いと記述量が多くなり全体の見通しが悪くなります。また、テストを書くのも単純に手間が増えてしまうとう課題もあります。そこで自分は、3rd partyのテストライブラリを使って記述量を減らすようにしています。著名なパッケージとしては [testify](https://github.com/stretchr/testify) が挙げられます。

```go
resp, err := mypkg.MyFunc()
require.NoError(t, err)
assert.Equal(t, "ok", resp)

```

これによって記述量はだいぶ少なくすることができるのですが、一つ問題があります。Go1.18でGenericsが登場する前は任意の型を関数に渡すためには `interface{}` （現代では `any` ）を引数に指定し、 `reflect` パッケージによって型の検査などをするしか方法がありませんでした。これによって以下のような弊害があります。

- 期待するデータの型と実際に検査するデータの型が一致しているかがテストを実行するまでわからない。なんならテストが開始したあとも実際に比較されるまでわからない
- 型がわからないことによってエディタの補完機能の恩恵を受けにくい
- 違う型を渡した場合の挙動が想像しにくい

もし事前に型の検査ができるのであればエディタ上で間違いを確認でき、開発体験の向上が期待できます。

# Genericsを使ってテストユーティリティを作る

ということでせっかくGenerics が使えるようになったんだから、ちゃんと型を検査できるようにしたい、というモチベーションからテストユーティリティを作成しました。紆余曲折を経て、Method Chain形式でテストを記述できるようになっています。

```go
users := getUsers()

// 配列の長さが5で Name が "blue" の要素を含むかを検査する
gt.Array(t, users).
	Length(5).
	Have(&user{Name:"blue"})

```

Genericsを使うことで、書式や型チェックをするlinterを入れていれば、エディタ上で違う型を比較しようとしていることがわかるようになります。

![](https://storage.googleapis.com/zenn-user-upload/8880985a8fb6-20230104.png)

テストは失敗すると、型にあったメッセージをだします。 `struct` の場合は差分をだすようにしています。

```go
gt.Value(t, u1).Equal(&User{
	ID:   "123",
	Name: "orange",
})
```

```go
=== RUN   TestFailure
    value_test.go:235: values are not matched
        diff:
          &gt_test.User{
                ID:   "123",
        -       Name: "orange",
        +       Name: "blue",
          }
```


例えば数値の場合は比較内容に応じたメッセージになるようにしています。

```go
gt.Number(t, v).Greater(12)
```


```go
=== RUN   TestFailure/number
    value_test.go:250: got 10, want grater than 12
```

## 変数のテスト

テストはいくつかの型を用意し、それぞれに対応した検査機能を実装しました。

- `Value` どの値でも使える代わりに基本的なテストのみ
- `Number` 数値を対象とし、大小比較などのテストがある
- `Array` slice + array を対象とし、配列の長さやサブシーケンスのテストがある
- `Map` mapを対象とし、キーや値に関するテストがある

例えば `Map` の場合はキーの所持や値の所持の確認ができますが、他の型ではそのような必要はないので、 `Map` だけに実装されています。

```go
colors := map[string]int{
  "white": 0,
  "red": 1,
  "blue": 5,
}

gt.Map(t, colors).
	HaveKey("white").      // キーの存在チェック。これはPass
	HaveValue(5).          // 値の存在チェック、これもPass
	HaveKeyValue("red", 2) // キーと値の組み合わせチェック。これはFailになる
```

他にも「大小比較」は数値にしか必要ないので、数値型でのみ実装されています。

```go
age := 29

gt.Number(t, age).Greater(20).Less(30)
```

これによって比較する値同士の型の一致を確認できるだけでなく、形式に応じたテスト（そしてキーや値の型のチェックもできる）を絞り、テストを記述する際に必要な選択肢だけを確認できるようになります。

## 事前の型チェック

`Array` や `Map` については以下のようにすることで、そもそも配列やmap型のみを受け付けられるようにしています。

```go
func Map[K comparable, V any](t testing.TB, actual map[K]V) MapTest[K, V] {
  // snip
}

func Array[T comparable](t testing.TB, actual []T) ArrayTest[T] {
  // snip
}
```

また `Number` は以下のようにすることで、数値型のみを受け付けるようになっています。

```go
type number interface {
	int | uint |
		int8 | int16 | int32 | int64 |
		uint8 | uint16 | uint32 | uint64 |
		float32 | float64
}

func Number[T number](t testing.TB, actual T) NumberTest[T] {
// ...(snip)...
```

ユーザ定義のカスタム型の場合、reflectを使ったテストだと値が同じでも違う型として扱われてテストがFailするケースがありますが、Genericsを使った場合は型として一致しうるかを事前に推定してくれます。

```go
type password string
var p password = "xxx"

// 値は同じだが "xxx" はstringとみなされる
assert.Equal(t, "xxx", p) // Fail

// gt.Valueで扱うのが password型であることが決まるため、 "xxx" もpassword型として扱われる
gt.Value(r, p).Equal("xxx") // Pass

```

## 型判定のテスト

また、変則的なものとして type assertion のテストもできるようにしてみました。従来の書き方だと、

```go
v, ok := resp.(*User)
if !ok {
  t.Error("type is not matched")
}
if v == nil {
  t.Error("v should not nil")
}
```

のように記述する必要がありましたが、Genericsを使うことでこのような記述もできます。

```go
// type assertionに失敗する、あるいはnilだった場合にFail
v := gt.Cast[*User](t, resp).NotNil()
```

# 余談：ボツ案 Functional Options Pattern

別案として[Functioanl Option Pattern](https://dave.cheney.net/2014/10/17/functional-options-for-friendly-apis)で実装するという手も考えられました。例えばこういう感じです。

```go
title := "my fair lady"
gt.Value(t, title,
	gt.Contain("my"),
)

```

こちらのほうがGoっぽいのでいいかなと思ったのですが、この方法だとオプション側で明示的に指定しないと型推論が働きません。例えば仮に文字列長さをチェックする `Length` というオプションを使おうとした場合、

```go
title := "my fair lady"
gt.Value(t, title,
	gt.Contain("my"),
	gt.Length(12), // ← コンパイルエラー
)
```

という書き方はエラーになってしまいます。これはどう記述すればいいかと言うと、

```go
title := "my fair lady"
gt.Value(t, title,
	gt.Contain("my"),
	gt.Length[string](12),
)
```

となります。 `Contain` の方は引数が `string` なのでそれによって型が決定しています。これだと記述する側の体験に影響しそうというのと、Method Chain 形式でもそれほど記述量などが変わらないことから、現状の形式にしました。

# まとめ

GoはGenericsがなくても十分な記述力のある言語と思っていましたが、やはりGenericsを活用して適切に型をチェックできるようになることでよりコードが書きやすくなったと感じています。これまで `interface{}` や `reflect` によって裏技的に解決していたものがより適切に記述できるようになり、生産性にも良い影響があると考えています。Genericsは使い方によってはコードの可読性を下げてしまうため乱用は避けたいですが、適切に運用することでより開発体験を高める試みは今後もやっていきたいと思います。