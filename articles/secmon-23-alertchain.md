---
title: "実践セキュリティ監視基盤構築(23): アラート対応の自動化の実装例"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の23日目です。本日はアラート対応の自動化をするための実装を紹介します。

# アラート対応の自動化の要件

あらためてアラート対応の自動化の実装要件を整理します。

- ✔ **柔軟な分岐とロジックの表現**: アラートの内容によって処理内容や対象を変更するなどしたいことから、ロジックを柔軟に表現できる必要があります。これは分岐だけでなく、アラートに含まれる値や構造データを自由に加工・比較できることが望ましいです。
- ✔ **テスト可能性・自動化**: アラート対応の自動化は、アラートの内容によって処理が変わることが多いため、そのロジックが期待通りに動作するかを検証することが必要です。そのためにテストができるフレームワークを用意しておくことが重要です。
- ✔ **アラートの集約・紐づけ**: 大量のアラートが発生すると、その処理によって外部サービスなどに過負荷をかける恐れがあります。また、アラートの数が多いと担当者やセキュリティアナリストが捌く手間が大きくなってしまいます。これらをうまく集約することで対応する人物の手間と認知負荷を軽減し、適切な対応を促すことができます。

# アラート対応の自動化実装: AlertChain

こういった要件を満たすための一つの実装例として、[AlertChain](https://github.com/secmon-lab/alertchain)というOSSを紹介します。AlertChainは、アラートの受付から対応までを[Rego](https://www.openpolicyagent.org/docs/latest/)ルールで記述できるツールです。

https://github.com/secmon-lab/alertchain

AlertChainは大きく分けて2つのルールで構成されています。1つがアラートの受付を行う `alert` ポリシー、もう1つがアラートの対応をするアクションを決定する `action` ポリシーです。これらのポリシーはRegoで記述され、アラートの内容に応じて処理を分岐させることができます。

[Rego](https://www.openpolicyagent.org/docs/latest/)は外部入出力などの機能を原則としてもたず、それでいて柔軟なロジックを記述できるため、アラートの内容に応じて処理を分岐させるといった要件に適しています。また、Regoはテストフレームワークが提供されており、記述したルールが期待通りに動作するかを検証することができます。

![](https://storage.googleapis.com/zenn-user-upload/2cdbbd8f7d19-20241215.png)

上記はAlertChainの全体的な処理の流れを表現しています。AlertChainはHTTP APIからアラートを受け付け、そのアラートをRegoルールに基づいて処理します。最初に `alert` ポリシーによってアラートを受け付けるかの判断をしつつ、AlertChain内でアラートとして扱うためのデータの正規化をします。その後、 `action` ポリシーによってどのようなアクションを取るかを決定し、そのアクションを実行します。アクションは主に外部サービスへの通知、チケット作成、アラートの分析のような処理が用意されており、実行順序や実行時のパラメータなどをRegoによって柔軟に記述できる、というのが大きな特徴です。

# AlertChainの特徴

## アラート受付のためのRegoルール ( `alert` ポリシー)

AlertChainはアラートの受付を行うための `alert` ポリシーをRegoで記述します。このポリシーは受信したアラートをAlertChain内部で流通させられるように正規化するとともに、アラートを受け入れるか、あるいは無視するかの選択をできるようにしています。これは、受け付けるアラートが自分たちで制御可能な監視基盤上のアラート検知コンポーネントだけでなく、外部システム・サービスから発報されるアラートも受け付けるためです。外部システム・サービス内に一部のアラートを無視させる機能を持つ場合もありますが、そういった機能が何もなくこちら側で制御しなければならないものもあり、このような機能を持ちます。

例えば以下のように記述します。

```rego
package alert.aws_guardduty

alert contains {
    "title": f.Type,
    "source": "aws",
    "description": f.Description,
    "attrs": [
        {
            "key": "instance ID",
            "value": f.Resource.InstanceDetails.InstanceId,
        },
        {
            "key": "Requested Domain",
            "value": f.Service.Action.DnsRequestAction.Domain,
        },
    ],
} if {
    f := input.Findings[_]
    startswith(f.Type, "Trojan:")
    f.Severity > 7
}
```

このルールはAmazon GuardDutyのFindingをアラートとして受信したことを想定します。具体的には以下のようなデータがHTTP APIで渡されたと想定してください。

https://github.com/secmon-lab/alertchain/blob/main/examples/basic/guardduty.json

具体的な動作について見ていきます。

```rego
f := input.Findings[_]
startswith(f.Type, "Trojan:")
f.Severity > 7
```

まず上記の3行は受け付けたデータからアラートとして取り扱う部分を抽出し、それを受け入れるか判定しています。`.Findings` が配列なので1つずつとりだし (1行目) 、`.Findings[].Type` のPrefixが `Trojan:` であるかを判定し (2行目) 、そして `Findings[].Severity` が7より大きいかを判定します (3行目)。これらが揃った場合 (AND条件) にのみ、アラートとして受け入れるというルールになっています。この条件に合致しなかった場合、アラートは受け入れられず後続の処理は実行されません。

```rego
alert contains {
    "title": f.Type,
    "source": "aws",
    "description": f.Description,
    "attrs": [
        {
            "key": "instance ID",
            "value": f.Resource.InstanceDetails.InstanceId,
        },
        {
            "key": "Requested Domain",
            "value": f.Service.Action.DnsRequestAction.Domain,
        },
    ],
    "namespace": sprintf("aws_guardduty_trojan_alert/instance/%s", [f.Resource.InstanceDetails.InstanceId]),
}
```

次はアラートとして受けいれる場合の正規化の処理です。この例では、アラートのタイトル `title` 、アラートの発報元 `source`、説明 `description`、および属性を抽出しています。属性は `attrs` という配列で表現され、それぞれの属性は `key` と `value` で表現されています。このようにして、アラートとして渡されたデータから後続の処理や記録に必要な情報を抽出しています。

設定される属性値は原則としてそのアラートにのみ紐づけされますが、要件でも説明した通りアラート間でのデータ連携が必要な場合もあります。そのため、この例では `namespace` という属性を追加しています。この属性はアラートの名前空間を表現し、他のアラートとの関連付けを行うための情報として利用されます。今回は `namespace` にEC2インスタンスIDを利用しており、これによって同じインスタンス上で発生した異なるアラートで名前空間が共有されることになります。後述するアラート対応のアクションでこの名前空間を利用してアラート間のデータ連携ができるようになっています。

## アラート対応のためのRegoルール ( `action` ポリシー)

アラートとして受け入れられた後は、アラートの内容に応じてどのようなアクションをするかを決定するルールが呼び出されます。このルールは `action` ポリシーとしてRegoで記述されます。このポリシーはアラートの内容に応じて、通知やチケット作成、アラートの分析などのアクションを決定します。

`action` ルールは[AWS Step Functions](https://aws.amazon.com/step-functions/?nc1=h_ls)と似たような発想で、各アクションはステートマシンのように連鎖していきます。AlertChainはアラートを受け入れた後に、`action` ポリシーを評価して `run` というルールに格納された情報に基づいてアクションを実行します。`run` にはいくつでもアクションを記述でき、指定された分だけ順次実行されます。これらの実行が終わったらAlertChainは再度 `action` ポリシーを評価して、`run` ルールで指定されたアクションを実行します。これを繰り返して「`run`ルールに何も格納されない」「`run`ルールで指定されたアクションが全て実行済み」という条件が満たされるまで繰り返します。

```rego
package action

# (1) ChatGPTによるアラート内容の分析
run contains {
    "id": "ask-chatgpt",
    "uses": "chatgpt.query",
    "args": {
        "secret_api_key": input.env.CHATGPT_API_KEY,
        "prompt": "Analyze and summarize the given JSON-formatted security alert data",
    },
    "commit": [
        {
            "key": "ChatGPT's comment",
            "path": "choices[0].message.content",
        },
    ],
} if {
    input.seq == 0
}

# (2) ChatGPTの結果を添えてSlackに通知を送る処理
run contains {
    "id": "notify-slack",
    "uses": "slack.post",
    "args": {
        "secret_webhook_url": input.env.SLACK_INCOMING_WEBHOOK,
    },
} if {
    input.called[_].id == "ask-chatgpt"
}
```

この例では、アラートの内容に応じて2つのアクションを行います。1つ目のアクションはChatGPTを使ってアラートの内容を分析し、その結果を取得するというものです。2つ目のアクションはSlackに通知を送るというものです。この例ではChatGPTの結果をSlackに通知するという処理を行っています。

この例ではChatGPTの結果を取得した後にSlackに通知を送るという処理を行っています。これは `action` ポリシーが評価される際に渡される `input.seq` と `input.called` という入力によって実行順序が制御されています。`input.seq` は `action` ポリシーが評価された回数を表し、`input.called` はこれまでのアクションの実行結果が格納されています。まず `seq` が0、つまり最初に評価された場合にはChatGPTを使ってアラートの内容を分析するアクションを実行し、そのあとで `input.called` という配列に `id` が `ask-chatgpt` であるアクションが含まれていた場合にはSlackに通知を送るアクションを実行する、という順序の制御が行われています。

## 集約・紐づけのためのアラート間データ連携

AlertChainにおけるアラート間のデータ連携は、アラートの受付時に設定される `namespace` という属性を利用して行います。この属性はアラートの名前空間を表現し、他のアラートとの関連付けを行うための情報として利用されます。アラートの受付時に設定された `namespace` は、そのアラートが属する名前空間を表現します。

先述した例では以下のような `namespace` を設定していました。

```rego
    "namespace": sprintf("aws_guardduty_trojan_alert/instance/%s", [f.Resource.InstanceDetails.InstanceId]),
```

この `namespace` は同じEC2インスタンス上で発生した異なるアラートで共有されることになります。そしてアラートの `attrs` で属性値を追加する際に `persist` というフィールドに `true` を指定することで、その値はデータベース（Firestore）に保存され、同じ `namespace` をもつアラートが発生した際には保存された値が取得されて `attrs` に追加されます。これによってアラート間でのデータ連携が可能になります。

例として、最初のアラートでGitHubのIssueを作成、同一のEC2インスタンス上で発生した異なるアラートがあった場合はコメントをする、という `action` ポリシーを以下に示します。

```rego
package action

github_args := {
    "app_id": 134650,
    "install_id": 19102538,
    "owner": "m-mizutani",
    "repo": "security-alert",
    "secret_private_key": input.env.GITHUB_PRIVATE_KEY,
}

issue_num := input.alert.attrs[x].value if {
    input.alert.attrs[x].key == "github_issue_number"
}

# (1) GitHub issue number が存在しなければIssueを作成
run contains {
    "id": "github-issue",
    "uses": "github.create_issue",
    "args": github_args,
    "commit": [
        {
            "key": "github_issue_number",
            "global": true,
            "path": "number",
        },
    ],
} if {
    not issue_num
}

# (2) GitHub issue number が存在するなら、それをもとにコメントを作成
run contains {
    "id": "github-comment",
    "uses": "github.create_comment",
    "args": object.union(github_args, {
        "body": "dup!",
        "issue_number": issue_num,
    }),
} if {
    issue_num
}
```

要点を見ていきましょう。

```rego
github_issue_number := input.alert.attrs[x].value if {
    input.alert.attrs[x].key == "github_issue_number"
}
```

まず、上記のルールで `attrs` の中から `github_issue_number` を取得して `issue_num` という変数に格納しています。もし `github_issue_number` というキーを持つ属性が存在しない場合は、 `issue_num` は未定義となります。

```rego
    "commit": [
        {
            "key": "github_issue_number",
            "path": "number",
            "persist": true,
        },
    ],
```

`issue_num` が未定義だった場合、(1)の処理が実行されます。この処理ではGitHubのIssueを作成し、その際の[返り値](https://docs.github.com/en/rest/issues/issues?apiVersion=2022-11-28#create-an-issue)を扱うことができます。そして `commit` というフィールドは処理実行後に保存する属性値を指定することができ、保存する値は `path` でJSONPathを指定してIssue作成APIの返り値から取得することができます。今回はIssueの番号を取得・保存したいので `number` というフィールドから値を取出します。さらに `persist` を指定することで、値を永続化します。

```rego
    "args": object.union(github_args, {
        "issue_number": issue_num,
    }),
```

(2)の処理は `issue_num` が定義済みであれば実行されます。この処理では、GitHubのIssueにコメントを追加する処理を行っています。この処理は先程のIssue作成のときに指定した引数以外に、 `issue_number` を指定することで、どのIssueにコメントを追加するかを指定しています。
ここで `issue_num` をセットすることで、同じEC2インスタンス上で発生した異なるアラートがあった場合、Issue番号を取得し、そのIssueにコメントを追加するという処理が行われます。

このような関連付け方法は逐次的なものであり、事前にルールとして記述しておかなければならないというデメリットがあります。しかし決定性を持つため、アラートを取りこぼしたり期待されない関連付けが起こらないという利点があり、今回の実装ではこの利点を重要視しました。

## テスト

AlertChainは主にアラート受入とアラート対応でロジックを持ちます。それぞれに対してテストが実施できる必要があり、異なる方法でテストが実現できるようになっています。

### アラート受入処理のテスト

アラート受入のテストは[OPA/Regoのテスト機能](https://www.openpolicyagent.org/docs/latest/policy-reference/#tests)をそのまま利用します。Regoの実行ランタイムであるOPAには、Regoのテストを実行するためのCLIが用意されており、これを利用してテストを実行することができます。

先程の例で示した `alert` ポリシーをもとに簡略化したルールでテストを実装してみます。以下に説明のため簡略化したルールを示します。 `alert.rego`, `alert_test.rego`, `testdata/guardduty/data.json` （[これ](https://github.com/secmon-lab/alertchain/blob/main/examples/basic/guardduty.json)と同じ）というファイルを作成します。

```rego:alert.rego
package alert.aws_guardduty

alert contains {
    "title": f.Type,
    "source": "aws",
    "attrs": [
        {
            "key": "instance ID",
            "value": f.Resource.InstanceDetails.InstanceId,
        },
    ],
} if {
    f := input.Findings[_]
    startswith(f.Type, "Trojan:")
    f.Severity > 7
}
```

そしてテストをいくつか記述してみます。まずは正常にアラートとして検知する場合のテストです。

```rego:alert_test.rego
test_alert if {
	resp := alert with input as data.testdata.guardduty
	count(resp) == 1
	a := resp[_]
	a.title == "Trojan:EC2/DropPoint!DNS"
	count(a.attrs) == 1
	a.attrs[x].key == "instance ID"
	a.attrs[x].value == "i-99999999"
}
```

このテストは、 `testdata/guardduty/data.json` に記述されたデータを `alert` ルールに適用した結果が正しいかを検証しています。テスト用データは検知が期待されるアラートの内容となっています。これを `alert with input as data.testdata.guardduty` とすることで `input` の値を上書きした上で `alert` ルールを評価して、その結果を `resp` に格納します。そして `resp` に対してタイトルや属性値の検証を行っています。

```rego:alert_test.rego
test_not_enough_severity if {
	resp := alert with input as json.patch(data.testdata.guardduty, [
        {
            "op": "replace",
            "path": "/Findings/0/Severity",
            "value": 7
        }
    ])

	count(resp) == 0
}
```

次に、アラートの重要度が7未満の場合にアラートとして検知されないことを検証するテストを記述します。このテストでは、 `Severity` の値を7未満に変更したデータを `alert` ルールに適用した結果が空であることを検証しています。テスト用データをテストの数だけ用意しても良いのですが、手間がかかるため筆者は `json.patch` という関数を利用してテスト用データを変更することが多いです。

```rego:alert_test.rego
test_not_trojan if {
    resp := alert with input as json.patch(data.testdata.guardduty, [
        {
            "op": "replace",
            "path": "/Findings/0/Type",
            "value": "NotTrojan:EC2/DropPoint!DNS"
        }
    ])

    count(resp) == 0
}
```

さらに、アラートのタイプが `Trojan:` で始まらない場合にアラートとして検知されないことを検証するテストを記述します。このテストでは、 `Type` の値を `Trojan:` で始まらない値に変更したデータを `alert` ルールに適用した結果が空であることを検証しています。

これらのテストを実行するには、OPAのCLIを利用します。以下のコマンドを実行することでテストを実行できます。

```sh
$ tree .
.
├── alert.rego
├── alert_test.rego
└── testdata
    └── guardduty
        └── data.json

3 directories, 3 files

$ opa test -v .
alert_test.rego:
data.alert.aws_guardduty.test_alert: PASS (689.792µs)
data.alert.aws_guardduty.test_not_enough_severity: PASS (389.833µs)
data.alert.aws_guardduty.test_not_trojan: PASS (317.792µs)
--------------------------------------------------------------------------------
PASS: 3/3
```

### アラート対応処理のテスト



# まとめ
