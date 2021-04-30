---
title: "AWS CDKでシンプルなReact Webアプリをデプロイする"
emoji: "💨"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [aws,react,awscdk,lambda,typescript]
published: true
---

ちょっとしたWebアプリやたまにしか使わない管理用アプリをデプロイしたいと思った時にAWS CDK + Reactで簡単に使えるテンプレートを作ったので紹介の記事を書いてみます。

コードは以下に置いてあります。

https://github.com/m-mizutani/boilerplate-cdk-react-app

前提となる考え方は以下の通りです。

- 対外向けのちゃんとしたサービスではなく内向き・個人用であり、アクセス頻度は高くないことを想定
- なるべく低コストかつpay per useで使った分だけコストを支払う
- 管理の手間などから構成は極力シンプルにする

なお著者はTypeScriptは初心者なので、本記事よりよいベストプラクティスがあるかもしれません。

# 構築手順

### 初期化

まず最初にアプリのディレクトリを掘ります。

```bash
$ mkdir your-awesome-app
$ cd your-awesome-app
```

その後ディレクトリ内に移動してCDKの初期化と必要なディレクトリを作成します。

```bash
$ cdk init --language typescript
$ mkdir lib/backend
$ mkdir lib/backend/api
$ cd lib/backend && npm init -y && cd ../..
$ mkdir lib/frontend
$ mkdir lib/frontend/src
$ mkdir lib/frontend/dist
$ cd lib/frontend && npm init -y && cd ../..
```

その後、`package.json` 内の `dependencies`　に以下の項目を加えます。バージョン番号は先に記載されているはずの `@aws-cdk/core` に全て揃える必要があります。（ここでは `1.90.0` ）

```json:package.json
    "@aws-cdk/aws-lambda": "1.90.0",
    "@aws-cdk/aws-iam": "1.90.0",
    "@aws-cdk/aws-dynamodb": "1.90.0",
    "@aws-cdk/aws-apigateway": "1.90.0",
```

その後、 `npm i` で必要なパッケージをインストールします。

### バックエンドの作成

次にバックエンドで動くLambdaを作成します。まず各種パッケージをインストールします。

```bash
$ cd lib/backend
$ npm i aws-sdk aws-lambda aws-serverless-express express @types/aws-serverless-express @types/express
```

`lib/backend/api`. 内に`main.ts` と `app.ts` を用意します。これはあとから `app.ts` を開発用ローカルサーバで呼び出したいために分割しています。ここではシンプルに `/api/v1/message` のエンドポイントしか作成しません。


```ts:lib/backend/api/app.ts
import * as express from "express";

const app = express();

app.get("/api/v1/message", (req: express.Request, res: express.Response) => {
  res.send({ message: "Hello, Hello, Hello" });
});
app.use(express.static("assets"));

export default app;
```

このコードでは後に説明するフロントエンド用のコード（今回は`index.html` + `bundle.js`）を `assets` 以下に配置し、それをAPI gateway経由で応答させます。今回は低頻度かつ対外的に利用しないという前提のため、API gatewayを受けるLambda内に全て同梱させます。

:::message
**Alternatives**
- 大量のアクセスが見込まれる場合はスケーラビリティやコストの観点からフロントエンド用のコードをS3に配置し、CloudFrontなどを経由してアクセスさせる方法があります
- [API gatewayでproxyを設定してS3に配置したファイルにアクセスさせる方法](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-s3.html)もあります
:::

```ts:lib/backend/api/main.ts
import * as awsServerlessExpress from "aws-serverless-express";
import * as lambda from "aws-lambda";

import app from "./app";

const server = awsServerlessExpress.createServer(app);

export function handler(
  event: lambda.APIGatewayProxyEvent,
  context: lambda.Context
) {
  awsServerlessExpress.proxy(server, event, context);
}
```

また、 `tsconfig.json` も `lib/backend` に用意します。

```json:lib/backend/tsconfig.json
{
  "compilerOptions": {
    "target": "ES2018",
    "module": "commonjs",
    "lib": ["es2018"],
    "typeRoots": ["./node_modules/@types"]
  }
}
```

### フロントエンドの作成

今度は `lib/frontend/` に移動してフロントエンドに必要なファイルを用意します。まずは必要なパッケージ類をインストール。

```bash
$ npm i -D ts-loader typescript webpack webpack-cli webpack-dev-server
$ npm i @types/react @types/react-dom react react-dom
```

設定がやや違うため、別途バックエンド用とは別に `lib/frontend/tsconfig.json` も作成します。

```json:lib/frontend/tsconfig.json
{
  "compilerOptions": {
    "sourceMap": true,
    "target": "es5",
    "module": "es2015",
    "jsx": "react",
    "moduleResolution": "node",
    "allowSyntheticDefaultImports": true,
    "lib": ["es2020", "dom"]
  }
}
```

WebpackでJSを一纏めにするため `lib/frontend/webpack.config.js` を用意します。開発時にはAPIを別プロセスで動かすので、 `devServer` で `/api` 以下のリクエストを `http://localhsot:9080` へ貫通させます。

```js:lib/frontend/webpack.config.js
module.exports = {
  mode: "development",
  entry: "./src/js/main.tsx",
  output: {
    path: `${__dirname}/dist`,
    filename: "bundle.js",
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: "ts-loader",
      },
    ],
  },
  resolve: {
    extensions: [".ts", ".tsx", ".js", ".json"],
  },
  devServer: {
    contentBase: "dist",
    proxy: {
      "/api": "http://localhost:9080",
    },
    hot: true,
  },
  target: ["web", "es5"],
};
```

Reactアプリのメインとして `lib/frontend/src/js/main.tsx` を作成します。このコードでは `api/v1/message` にアクセスして受信した結果を表示さるだけの処理をします。

```tsx:lib/frontend/src/js/main.tsx
import * as React from "react";
import * as ReactDOM from "react-dom";

// 状態管理用の構造体
interface myAppState {
  isLoaded: boolean;
  msg?: string;
  error?: any;
}

const App: React.FC = () => {
  const [state, setState] = React.useState<myAppState>({ isLoaded: false });
  const showMessage = () => {
    // myAppState の状態によって表示させる内容を変更
    if (!state.isLoaded) {
      return <p>Loading</p>;
    } else if (state.msg) {
      return <p>msg: {state.msg}</p>;
    } else {
      return <p>Error: {state.error}</p>;
    }
  };

  // ページの初回ロード時に api/v1/message にアクセス
  React.useEffect(() => {
    /*
      API Gateway が発行したURLをそのまま使う場合、
      https://xxxxxxxxxxxx.execute-api.ap-northeast-1.amazonaws.com/prod/
      のように末尾にステージ名が自動で入ってrootが変わるため、 /api/v1/message にすると正しくアクセスできない
    */
    fetch("api/v1/message")
      .then((res) => {
        return res.json();
      })
      .then(
        (result) => {
          setState({ isLoaded: true, msg: result.message });
        },
        (error) => {
          setState({ isLoaded: true, error: "error" + error });
        }
      );
  }, []);

  return (
    <div>
      <h1>Welcome to my awesome app!</h1>
      {showMessage()}
    </div>
  );
};
ReactDOM.render(<App />, document.querySelector("#app"));
```

あとは最初の読み込みに使う `lib/frontend/dist/index.html` を用意して一旦完成です。

```html:lib/frontend/dist/index.html
<!DOCTYPE html>
<html>
  <head>
    <title>your awesome app</title>
    <meta charset="UTF-8" />
    <script defer src="bundle.js"></script>
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

この時点でローカルでの開発はできるようになるので、確認したい場合は [開発手順](#開発手順) を参照してください。

### CDKの設定

今回は以下のような非常にシンプルな設計になります。

![](https://storage.googleapis.com/zenn-user-upload/ttm6zzu07wedkpdvtkqrbus4a45y)

`lib/boilerplate-cdk-react-app-stack.ts` を編集して必要なリソースを追加します。(`boilerplate-cdk-react-app` の部分は作成したアプリの名前に置き換わります）

```ts:lib/boilerplate-cdk-react-app-stack.ts
    // Lambda を追加
    const asset = lambda.Code.fromAsset(__dirname, {
      bundling: {
        image: lambda.Runtime.NODEJS_14_X.bundlingDockerImage,
        user: "root",
        command: ["bash", "build.sh"],
      },
    });

    const apiHandler = new lambda.Function(this, "apiHandler", {
      runtime: lambda.Runtime.NODEJS_14_X,
      handler: "lambda/api/main.handler",
      code: asset,
      timeout: cdk.Duration.seconds(10),
      memorySize: 128,
    });

    // API Gatewayを追加
    const apiRoot = new apigateway.LambdaRestApi(this, "api", {
      handler: apiHandler,
      proxy: false,
      cloudWatchRole: false,
      endpointTypes: [apigateway.EndpointType.PRIVATE],
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            actions: ["execute-api:Invoke"],
            resources: ["execute-api:/*/*"],
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
          }),
        ],
      }),
    });

    // UI assets
    apiRoot.root.addMethod("GET");
    apiRoot.root.addResource("bundle.js").addMethod("GET");

    const v1 = apiRoot.root.addResource("api").addResource("v1");

    // message
    const repository = v1.addResource("message");
    repository.addMethod("GET");
```

そしてbundlingオプションによってLambda用のパッケージを作成する `build.sh` を用意します。

```bash:lib/build.sh
#!/bin/bash

ASSET_DIR=/asset-output
npm i -g npm
cd lambda && npm i && npm exec tsc && cd ..
cd frontend && npm i && npm exec webpack && cd ..
cp -rp lambda $ASSET_DIR
cp -rp frontend/dist $ASSET_DIR/assets
```

:::message
**Alternatives**
同じように実行用のコード以外（今回は静的コンテンツ）を同梱する方法として以下の選択肢があります
- [Lambda Layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html)を使う: 複数のLambdaで共有するデータを同梱するのが本来のユースケースかと思います。Layerと本体のLambdaが別管理になるので、バージョンを合わせる、あるいは同期させる仕組みを考える必要があります。
- [Lambda container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)を使う: 任意のファイルを含むコンテナイメージを作成しECRに登録して使う方法です。構成要素が増えることと、[コールドスタートが遅くなるらしい](https://mikhail.io/serverless/coldstarts/aws/)という点に注意が必要かもしれません。
:::

さらに `tsconfig.json` が `lib/frontend` および `lib/backend` に影響を及ぼさないよう、以下の通り編集します。

```json:tsconfig.json
  "exclude": ["cdk.out", "lib/frontend/", "lib/backend/"]
```

ここまで設定ができればデプロイが可能になります。[コマンドラインでAWSへのアクセス権限がある状態にして](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) `cdk deploy` を実行します。

```
$ cdk deploy
----- (snip) -----
 ✅  BoilerplateCdkReactAppStack

Outputs:
BoilerplateCdkReactAppStack.apiEndpoint9349E63C = https://xxxxxxxxxxxx.execute-api.ap-northeast-1.amazonaws.com/prod/

Stack ARN:
arn:aws:cloudformation:ap-northeast-1:111111111111:stack/BoilerplateCdkReactAppStack/3cd4e670-8ec1-11eb-8515-069db2e9c955
```

デプロイ画面の一番最後にでてきたURL（上記例だと https://xxxxxxxxxxxx.execute-api.ap-northeast-1.amazonaws.com/prod/ ）をブラウザで開くと、以下のような画面が表示されるはずです。

![](https://user-images.githubusercontent.com/605953/116548066-aa8eb100-a92e-11eb-9ae0-c047539d6305.png)
（URLはローカルのもの）

## 開発手順

開発する際、手元で動作を確認する方法です。

### ローカル用のAPIサーバを作成・立ち上げる

`lib/backend` 内で `npm -i -D ts-node` コマンドを実行した後、 `lib/backend/local/server.ts` を作成します。

```ts:lib/backend/local/server.ts
import app from "../api/app";

const port = 9080;
app.listen(port, () => {
  console.log(`Listening at http://localhost:${port}`);
});
```

その後、`npm exec ts-node ./local/server` でAPIサーバを立ち上げます。

### Webpack serverの立ち上げ

APIサーバとは別のコンソールを用意し、 `lib/frontend` から `npm exec webpack serve` でwebpackサーバを立ち上げます。

その後、http://localhost:8080/ にアクセスすることで開発画面を出すことができます。
