---
title: "⚙️ OPAをAWS Lambdaへデプロイ"
---


この節ではOPAの機能をAWS Lambdaで実装する方法について紹介します。

# AWS Lambda におけるOPA利用の戦略

AWS LambdaはFargateやGCP Cloud Runとは異なり、純粋に「関数」としての機能を提供しています。関数の呼び出しも各言語のSDKを経由する必要があり、既存のバイナリをそのまま利用するのは困難です。つまり GCP Cloud Run 、あるいは AWS ECS・Fargateのようにコンテナイメージやバイナリをそのまま使うことはできません。そのため、次の2つのどちらかの方針を検討する必要があります。

## 1) ランタイムを組み込んだLambda関数を自作する

`github.com/open-policy-agent/opa/rego` パッケージを取り込んだGo言語ベースのLambda関数を作り、デプロイする方法です。今回の記事ではこちらの方法を紹介します。

- メリット
    - 構成がシンプルになる：一般的なLambdaの利用方法にそった形になるので先行事例を参照しやすく、トラブル時の対応が比較的楽になると期待されます
    - パフォーマンスが（若干）良くなることが期待される：1つのプロセスだけで動かすため、メモリの消費量などで比較的有利になります
- デメリット
    - 自分でコードを書く必要がある：例えば複数のポリシーファイルを使いたい等の場合に、そのあたりの制御を自分で実装する必要があります。ただこれはopaコマンドの制約に縛られないという見方もできます
    - プログラミング言語が制限される：現状だと、OPAのランタイムで使われているGo言語、あるいは[WASMが提供されているnode](https://github.com/open-policy-agent/npm-opa-wasm)のどちらかが現実的な選択肢になります

## 2) opaコマンドを同梱してLambda関数をデプロイし、起動させる

Lambda関数は実行に必要なバイナリなどをアセットと呼ばれるアーカイブにまとめてそれを展開し起動します。そこでそのアセットにopaコマンド自体を同梱させ、Lambda関数から別プロセスとして起動させる方法です。

- メリット
    - opaコマンドの恩恵を受けられる：ポリシー管理などの側面で、opaコマンドで実装されているものがそのまま利用できます
    - プログラミング言語は自由に選択できる：コマンドを起動すればいいだけなので、現状Lambdaでサポートされている言語であればどれでも利用できます
- デメリット
    - パフォーマンスが（若干）悪いかもしれない：一概には言えませんが、Lambda内部でさらにもう1つプロセスを動かすことになるため、Lambdaから直接呼ばれるコードだけで処理するのに比べるとパフォーマンス的に不利な可能性があります。1分間に数回呼ばれる程度であれば問題にならないと思われますが、毎秒数十、数百回呼ばれるような使われ方の場合は大きくコストに差ができる可能性があります
    - 構成が複雑になる：Lambda内部で別プロセスを起動するというのはやや裏技的な使い方であり、先行事例もあまり多くはありません。またバイナリを同梱するのにもコツが必要だったり、トラブル時にプロセス内部の状況を見ながらデバッグすることができないなどの制約があるため、運用には一定の筋力が必要になります

# AWS Lambda + OPA のユースケース

ではそんな面倒なことをしてLambdaでOPAを使う必要があるのか（Fargateなどで使えばいいのではないか）という疑問に対して、いくつかユースケースを紹介します。

- Cloudfront Lambda@Edge：Cloudfront経由で送られてきたHTTPリクエストをLambdaで受けて認可の制御ができるため、その認可ポリシーをRegoで記述して管理するという使い方ができます
- Kinesis Data Firehose：Lambdaを使ったtransform機能があり、レコードの変更やレコードをドロップする、などの判定をRegoで記述して管理できます
- API gateway：ポリシーの判定が稀にしか発生しない場合、HTTPリクエストをAPI gatewayで受け取りLambda内のRegoで判定した結果をそのまま応答するという構成にすることで、Fargateなどでの起動に比べて大幅にコストを削減できます
- CloudWatch Event：AWS内で発生した様々なイベントをCloudWatch経由でLambdaが受け取れます。事象が起こった後なのでリクエストの中止はできませんが、リソースの変更を上書きしたり、イベントの発生を通知する、というような部分の判定にRegoを利用できます

# デプロイの方法

コードについては以下に置いてあるので適宜ご参照ください。
https://github.com/m-mizutani/rego-sandbox/tree/main/integration/cdk

## Prerequisite

以下のツールがセットアップ済みとします。

- [go](https://go.dev/doc/tutorial/getting-started) >= 1.17
- [Node.js and npm](https://nodejs.org/en/download/package-manager/) >= v17.0.1
- [AWS CDK](https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html#getting_started_install) >= 1.134.0

## CDKアプリの作成

一般的な手順でCDK用のディレクトリを作成し、必要なモジュールも追加します。

```bash
$ mkdir cdk
$ cd cdk
$ cdk init --language typescript
$ npm i @aws-cdk/aws-lambda
```

CDKのstackを作成します。今回はサンプルということで最低限のLambdaだけデプロイします。

```ts:lib/cdk.ts
import * as cdk from "@aws-cdk/core";
import * as lambda from "@aws-cdk/aws-lambda";

export class CdkStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    new lambda.Function(this, "main", {
      runtime: lambda.Runtime.GO_1_X,
      // ./build/main にコンパイル済みバイナリが置かれる想定
      handler: "main",
      code: lambda.Code.fromAsset("./build"),
    });
  }
}
```

```ts:bin/cdk.ts
#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "@aws-cdk/core";
import { CdkStack } from "../lib/cdk-stack";

const app = new cdk.App();
new CdkStack(app, "opa-test", {
  env: {
    account: process.env.AWS_ACCOUNT,
    region: process.env.AWS_REGION,
  },
});
```

デプロイ時には環境変数で `AWS_ACCOUNT` (AWSアカウントID)、`AWS_REGION` (AWSのデプロイ先のリージョン) を設定する、もしくは `bin/cdk.ts` に直接値を書き込んでください。

また、CDKの利用が初めてのアカウント＆リージョンの場合は以下のコマンドでAWS側のセットアップが必要です。（例はアカウントIDが `111111111111`、リージョンが `us-east-1` の場合）

```bash
cdk bootstrap aws://111111111111/us-east-1
```

## Goのコード＆ポリシーの用意

`./lambda/main.go` に本体となるLambdaのコードを配置します。

```go:lambda/main.go
package main

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/open-policy-agent/opa/rego"
)

//go:embed policy/example.rego
var module string

func HandleRequest(ctx context.Context, input interface{}) (interface{}, error) {
	fmt.Println("input =>", input)

	q := rego.New(
		rego.Query(`x := data`),
		rego.Module("policy/example.rego", module),
		rego.Input(input),
	)

	rs, err := q.Eval(ctx)
	if err != nil {
		panic(err)
	}

	if len(rs) == 0 {
		return nil, nil
	}

	return rs[0].Bindings["x"], nil
}

func main() {
	lambda.Start(HandleRequest)
}
```

Regoポリシーを直接Goのコード内にハードコーディングすることもできますが、それだとRegoポリシーとしてのテストなどができなくなってしまいます。そこで上記例では `.rego` ファイル（上記例では `lambda/policy/example.rego` に配置されたファイル）をGo 1.16で導入された[embed機能](https://pkg.go.dev/embed)を利用して外部ファイルからGoのコードへ埋め込みます。

```rego:lambda/policy/example.rego
package example

allow {
    input.user == "mizutani"
}
```

他にも[CDKのbundling機能](https://aws.amazon.com/jp/blogs/devops/building-apps-with-aws-cdk/)を使って同梱させる方法もあり、必要に応じて選択できます。

## デプロイ

cdkコマンドでデプロイできます。手元から実行する際はコマンド実行時に[認証情報を設定する](https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds)必要がある点にご注意ください。

```bash
$ cdk deploy
opa-test: deploying...
[0%] start: Publishing 3b2c355b98c83def54cb691d70c2043ad8291728a3cd8c7bc5de1aeaf1a3f5b5:current
[100%] success: Published 3b2c355b98c83def54cb691d70c2043ad8291728a3cd8c7bc5de1aeaf1a3f5b5:current
opa-test: creating CloudFormation changeset...

 ✅  opa-test

Stack ARN:
arn:aws:cloudformation:ap-northeast-1:111111111111:stack/opa-test/91193c30-4f79-11ec-8483-06782e15d9b5
```

## コンソールから実行してみる

AWSコンソールからLambdaのページを開き、デプロイした関数を実行してみます。見つからない場合、CloudFormationのスタック一覧のページから探したほうが早いかもしれません。

ap-northeast-1の場合
- Lambda functions: https://ap-northeast-1.console.aws.amazon.com/lambda/home?region=ap-northeast-1#/functions
- CloudFormation stacks: https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks?filteringStatus=active&filteringText=&viewNested=true&hideStacks=false

![](https://storage.googleapis.com/zenn-user-upload/72df3f374753-20211128.png)

「テスト」タブを開きテスト用のJSONデータを記述し、変更を保存 → テストをクリックします。

![](https://storage.googleapis.com/zenn-user-upload/4230b714097a-20211128.png)

正しく実行されるとOPAで評価された結果が返されます。