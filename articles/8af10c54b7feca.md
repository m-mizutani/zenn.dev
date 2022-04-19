---
title: "手元の環境変数をいい感じに管理するzenv"
emoji: "📂"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["go", "cli"]
published: true
---

というのを作りました。

https://github.com/m-mizutani/zenv

# モチベーション

The Twelve Factor App の[設定](https://12factor.net/config)でも推奨されている通り、昨今のCommand Line Interface (CLI) で利用するアプリケーションやCLIでの開発では環境変数を多用します。これによって多くの環境変数を扱ったり、環境変数に秘匿値を扱ったり、文字数の多い環境変数を扱ったり、という機会も増えました。

環境変数を使うためにはシェルに設定したり、昔ながらの `env` コマンドを使ったり、[dotenv](https://www.npmjs.com/package/dotenv)を使ったり、秘匿値を扱う[envchain](https://github.com/sorah/envchain)などといった便利なツールが用意されています。しかし、

- それぞれを個別に使えるよりは統合的に環境変数を管理したい
- さらに高度な環境変数の設定機能を使いたい

という2つの観点から新しいツールを実装しました。

# 基本的な使い方

zenvの機能は大きく分けると、

- CLI上で環境変数を設定
- `.env` ファイルから環境変数を読み込み
- 秘匿値をKeychainに保存し、環境変数として読み込み（macOSのみ）

の3つになります。

まず、既存の `env` と同じように実行するコマンドの前に `名前=値` の形式で指定した環境変数をコマンドに渡すことができます。

```sh
$ zenv POSTGRES_DB=your_local_dev_db psql
```

また `dotenv` 系のツールと同じように、実行する際のディレクトリ（CWD）に `.env` ファイルを置くことで、その中身を読み取って環境変数としてコマンドに渡します。

```sh
$ cat .env
POSTGRES_DB=your_local_db
POSTGRES_USER=test_user
PGDATA=/var/lib/db
$ zenv psql -h localhost -p 15432
# connecting to your_local_db on localhost:15432 as test_user
```

さらに `zenv secret` というサブコマンドを使うことで、秘匿値をKeychainに保存・読み取りをします。

```sh
# save a secret value
$ zenv secret write @aws-account AWS_SECRET_ACCESS_KEY
Value: # ← 入力
$ zenv secret write @aws-account AWS_ACCESS_KEY_ID
Value: # ← 入力

# AWS_ACCESS_KEY_ID と AWS_SECRET_ACCESS_KEY を読み込んで "aws s3 ls" を実行する
$ zenv @aws-account aws s3 ls
2020-06-19 03:53:13 my-bucket1
2020-04-18 06:45:44 my-bucket2
...(snip)...
```

秘匿値を保存するための `secret write` は `zenv secret write <Namespace> <Key>` というフォーマットになります。上記例だと `@aws-account` が *Namespace* 、 `AWS_SECRET_ACCESS_KEY` および `AWS_ACCESS_KEY_ID` が *Key* (変数名)となります。読み込みは `zenv <Namespace> <コマンド>` という形式になり、*Namespace* に複数の変数が登録されている場合はそれらをすべて読み込んで、コマンドに渡します。

さらにこれらの全てを同時に扱うことができます。

```sh
$ zenv secret write @aws-account AWS_SECRET_ACCESS_KEY # 秘匿値だけ保存
Value: # ← 入力
$ cat .env # KEY IDは.envに入れる
AWS_ACCESS_KEY_ID=abcdefghijklmn
$ zenv @aws-account AWS_REGION=jp-northeast-1 aws s3 ls # AWS_REGION はCLIで設定
```

どのような環境変数が読み込まれたかを確認するためには `zenv list` を用意しています。これは現在設定されている全ての環境変数ではなく、`zenv` によって読み込まれたものだけを表示します。

```sh
$ zenv list @aws-account AWS_REGION=jp-northeast-1
AWS_REGION=jp-northeast-1
AWS_ACCESS_KEY_ID=abcdefghijklmn
AWS_SECRET_ACCESS_KEY=******************************** (hidden)
```

Keychainから読み込んだものについては、自動でマスクされるようになっています。

また、設定した *Namespace* の一覧も `zenv secret list` で取得できます。

```sh
$ zenv secret list
@aws
@local-db
@staging-db
```

## 高度な使い方

上記の基本以外にもいくつか変わった機能を実装しています。

### ランダムな文字列を生成して秘匿値として保存

`zenv secret generate` を利用することで、ランダムな文字列を生成してそのままKeychainに保存します。例えばローカルに開発用DBを設定するときなどに一度もパスワードを露出させずにセキュアな値を設定することができます。

```sh
$ zenv secret generate @my-project MYSQL_PASS
$ zenv secret generate @my-project -n 8 TMP_TOKEN # 長さを8文字にする
$ zenv list @my-project
MYSQL_PASS=******************************** (hidden)
TMP_TOKEN=******** (hidden)
```

### 秘匿値を保存したNamespaceを .env 内に記述する

名前空間を指定する *Namespace* はCLIで指定するだけでなく、 `.env` 内にも記載することができます。

```sh
$ zenv secret write @aws AWS_SECRET_ACCESS_KEY
Value # <- 入力

$ cat .env
@aws
# ↑ Namespace
AWS_REGION=jp-northeast-1
AWS_ACCESS_KEY_ID=abcdefghijklmn

$ zenv list
AWS_REGION=jp-northeast-1
AWS_ACCESS_KEY_ID=abcdefghijklmn
AWS_SECRET_ACCESS_KEY=******************************** (hidden)
```

これによって、そのディレクトリで使う秘匿値を都度指定する必要がなくなくなります。

### コマンドラインの中に環境変数を埋め込む

`env` はコマンドラインの中に埋め込まれた環境変数を置き換えることはできません。

```sh
$ env TEXT=hello echo "$TEXT"
# 何も表示されない
$ env TEXT=hello bash
$ echo "$TEXT"
hello # これは表示される
```

これはシェルによる変数の評価が `env` コマンドよりも先に実行されてしまうためです。`zenv` ではシェルによる変数の評価特別するため、`%` が接頭語になっているものをコマンドラインから探し、該当する環境変数を読み込んでいた場合は置換します。

```sh
$ cat .env
TOKEN=abc123
$ zenv curl -v -H "Authorization: bearer %TOKEN" http://localhost:1234
(snip)
> GET /api/v1/alert HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/7.64.1
> Accept: */*
> Authorization: bearer abc123
(snip)
```

### ファイルの中身を環境変数として読み込む

稀にですがやや大きいサイズのデータを環境変数に格納したい場合があります。例えばGoogle OAuth2のGo実装は[設定ファイルを直接読み込ませようとします](https://pkg.go.dev/golang.org/x/oauth2/google#CredentialsFromJSON)が、デプロイ構成の都合で環境変数のみ使いたい、というようなケースがあります。一方でローカル開発でも同じように環境変数として読み込みたい場合、設定自体はファイルとして管理して置いたほうが差し替えなどが便利です。

`zenv` は `.env` ファイルで指定した変数の値の先頭に `&` をつけることでファイルを読み込んでこれを環境変数としてコマンドに渡します。

```sh
$ cat .env
GOOGLE_OAUTH_DATA=&tmp/client_secret_00000-abcdefg.apps.googleusercontent.com.json
$ zenv list
GOOGLE_OAUTH_DATA={"web":{"client_id":"00000...(snip)..."}}
$ zenv ./some-oauth-server
```

### コマンドの実行結果を環境変数に設定する

`zenv` は両端がバッククオート `` ` `` で囲まれている値を指定した場合、これをコマンドとみなして実行し、その出力結果を環境変数としてコマンドに渡します。これは短期的に利用可能な認証トークンをコマンドで発行するようなユースケースで便利です。

```sh
$ cat .env
GOOGLE_TOKEN=`gcloud auth print-identity-token`
$ zenv list
GOOGLE_TOKEN=eyJhbGciOiJS...(snip)
$ zenv ./some-app-requires-token
```

# まとめ

ということで環境変数の管理が少しでも楽になれば幸いです。feature requestも可能な範囲で対応していきたいと思うので、気軽に[issue](https://github.com/m-mizutani/zenv/issues/new?labels=enhancement)あげてもらえればと思います。
