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
- ✔ **処理手続きにおける自由度の制限**: 一方で、アラート対応の処理自体の自由度が高すぎると、運用が複雑化し、メンテナンスが困難になる恐れがあります。規約などで統制するというアプローチもありますが、実装上で制限できるのが望ましいです。
- ✔ **テスト可能性・自動化**: アラート対応の自動化は、アラートの内容によって処理が変わることが多いため、そのロジックが期待通りに動作するかを検証することが必要です。そのためにテストができるフレームワークを用意しておくことが重要です。
- ✔ **アラートの集約・紐づけ**: 大量のアラートが発生すると、その処理によって外部サービスなどに過負荷をかける恐れがあります。また、アラートの数が多いと担当者やセキュリティアナリストが捌く手間が大きくなってしまいます。これらをうまく集約することで対応する人物の手間と認知負荷を軽減し、適切な対応を促すことができます。

# アラート対応の自動化実装: AlertChain

こういった要件を満たすための一つの実装例として、[AlertChain](https://github.com/secmon-lab/alertchain)というOSSを紹介します。AlertChainは、アラートの受付から対応までを[Rego](https://www.openpolicyagent.org/docs/latest/)ルールで記述できるツールです。

https://github.com/secmon-lab/alertchain

AlertChainは大きく分けて2つのルールで構成されています。1つがアラートの受付を行う `alert` ポリシー、もう1つがアラートの対応をするアクションを決定する `action` ポリシーです。これらのポリシーはRegoで記述され、アラートの内容に応じて処理を分岐させることができます。

![](https://storage.googleapis.com/zenn-user-upload/2cdbbd8f7d19-20241215.png)

上記はAlertChainの全体的な処理の流れを表現しています。AlertChainはHTTP APIからアラートを受け付け、そのアラートをRegoルールに基づいて処理します。最初に `alert` ポリシーによってアラートを受け付けるかの判断をしつつ、AlertChain内でアラートとして扱うためのデータの正規化をします。その後、 `action` ポリシーによってどのようなアクションを取るかを決定し、そのアクションを実行します。アクションは主に外部サービスへの通知、チケット作成、アラートの分析のような処理が用意されており、実行順序や実行時のパラメータなどをRegoによって柔軟に記述できる、というのが大きな特徴です。

# AlertChainの特徴

## アラート受付のためのRegoルール ( `alert` ポリシー)

AlertChainはアラートの受付を行うための `alert` ポリシーをRegoで記述します。このポリシーは受け付けたアラートをAlertChain内部で流通させられるように正規化するとともに、アラートを受け入れるか、あるいは無視するかの選択をできるようにしています。これは、受け付けるアラートが自分たちで制御可能な監視基盤上のアラート検知コンポーネントだけでなく、外部システム・サービスから発報されるアラートも受け付けるためです。外部システム・サービス内に一部のアラートを無視させる機能を持つ場合もありますが、そういった機能が何もなくこちら側で制御しなければならないものもあり、このような機能を持ちます。

例えば以下のように記述します。

```rego
package alert.aws_guardduty

alert[res] {
    f := input.Findings[_]
    startswith(f.Type, "Trojan:")
    f.Severity > 7

    res := {
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
    }
}
```

このルールはAmazon GuardDutyのFindingをアラートとして受信したことを想定します。具体的には以下のようなデータがHTTP APIで渡されたと想定してください。

```json
{
    "Findings": [
        {
            "AccountId": "783957204773",
            "Arn": "arn:aws:guardduty:ap-northeast-1:783957204773:detector/c6b248a96abef3c6dd24b07e13380b04/finding/034f3664616c49cb85349d0511ecd306",
            "CreatedAt": "2023-04-16T06:11:53.438Z",
            "Description": "EC2 instance i-99999999 is querying a domain name of a remote host that is known to hold credentials and other stolen data captured by malware.",
            "Id": "034f3664616c49cb85349d0511ecd306",
            "Partition": "aws",
            "Region": "ap-northeast-1",
            "Resource": {
                "InstanceDetails": {
                    "AvailabilityZone": "GeneratedFindingInstaceAvailabilityZone",
                    "IamInstanceProfile": {
                        "Arn": "arn:aws:iam::783957204773:example/instance/profile",
                        "Id": "GeneratedFindingInstanceProfileId"
                    },
                    "ImageDescription": "GeneratedFindingInstaceImageDescription",
                    "ImageId": "ami-99999999",
                    "InstanceId": "i-99999999",
                    "InstanceState": "running",
                    "InstanceType": "m3.xlarge",
                    --- 中略 ----
                },
                "ResourceType": "Instance"
            },
            "SchemaVersion": "2.0",
            "Service": {
                "Action": {
                    "ActionType": "DNS_REQUEST",
                    "DnsRequestAction": {
                        "Domain": "GeneratedFindingDomainName",
                        "Protocol": "UDP",
                        "Blocked": false
                    }
                },
                --- 中略 ---
            },
            "Severity": 8,
            "Title": "Drop Point domain name queried by EC2 instance i-99999999.",
            "Type": "Trojan:EC2/DropPoint!DNS",
            "UpdatedAt": "2023-04-16T06:11:53.438Z"
        }
    ]
}
```

具体的な動作について見ていきます。まず以下の3行は受け付けたデータからアラートとして取り扱う部分を抽出し、それを受け入れるか判定しています。`.Findings` が配列なので1つずつとりだし (1行目) 、`.Findings[].Type` のPrefixが `Trojan:` であるかを判定し (2行目) 、そして `Findings[].Severity` が7より大きいかを判定します (3行目)。これらが揃った場合（AND条件）にのみ、アラートとして受け入れるというルールになっています。

```rego
	f := input.Findings[_]
	startswith(f.Type, "Trojan:")
	f.Severity > 7
```

次はアラートとして受けいれる場合の正規化の処理です。この例では、アラートのタイトル `title` 、アラートの発報元 `source`、説明 `description`、および属性を抽出しています。属性は `attrs` という配列で表現され、それぞれの属性は `key` と `value` で表現されています。このようにして、アラートとして渡されたデータから後続の処理や記録に必要な情報を抽出しています。

```rego
res := {
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

設定される属性値は原則としてそのアラートにのみ紐づけされますが、要件でも説明した通りアラート間でのデータ連携が必要な場合もあります。そのため、この例では `namespace` という属性を追加しています。この属性はアラートの名前空間を表現し、他のアラートとの関連付けを行うための情報として利用されます。今回は `namespace` にEC2インスタンスIDを利用しており、これによって同じインスタンス上で発生した異なるアラートで名前空間が共有されることになります。後述するアラート対応のアクションでこの名前空間を利用してアラート間のデータ連携ができるようになっています。

## アラート対応のためのRegoルール ( `action` ポリシー)

アラートとして受け入れられた後は、アラートの内容に応じてどのようなアクションをするかを決定するルールが呼び出されます。このルールは `action` ポリシーとしてRegoで記述されます。このポリシーはアラートの内容に応じて、通知やチケット作成、アラートの分析などのアクションを決定します。

```rego
package action

run[{
    "id": "ask-chatgpt",
    "uses": "chatgpt.query",
    "args": {
        "secret_api_key": input.env.CHATGPT_API_KEY,
        "prompt": "Please analyze and summarize the given JSON-formatted security alert data",
    },
    "commit": [
        {
            "key": "ChatGPT's comment",
            "path": "choices[0].message.content",
        },
    ],
}] {
    input.seq == 0
}

run[{
    "id": "notify-slack",
    "uses": "slack.post",
    "args": {
        "secret_webhook_url": input.env.SLACK_INCOMING_WEBHOOK,
    },
}] {
    input.called[_].id == "ask-chatgpt"
}
```

この例では、アラートの内容に応じて2つのアクションを行います。1つ目のアクションはChatGPTを使ってアラートの内容を分析し、その結果を取得するというものです。2つ目のアクションはSlackに通知を送るというものです。この例ではChatGPTの結果をSlackに通知するという処理を行っています。

`action` ルールは[AWS Step Functions](https://aws.amazon.com/step-functions/?nc1=h_ls)と似たような発想で、各アクションはステートマシンのように連鎖していきます。AlertChainはアラートを受け付けた後に、`action` ポリシーを評価して `run` というルールに格納された情報に基づいてアクションを実行します。`run` にはいくつでもアクションを記述でき、指定された分だけ順次実行されます。これらの実行が終わったらAlertChainは再度 `action` ポリシーを評価して、`run` ルールで指定されたアクションを実行します。これを繰り返して「`run`ルールに何も格納されない」「`run`ルールで指定されたアクションが全て実行済み」という条件が満たされるまで繰り返します。

この例ではChatGPTの結果を取得した後にSlackに通知を送るという処理を行っています。これは `action` ポリシーが評価される際に渡される `input.seq` と `input.called` という入力によって実行順序が制御されています。`input.seq` は `action` ポリシーが評価された回数を表し、`input.called` はこれまでのアクションの実行結果が格納されています。 `seq` が0、つまり最初に評価された場合にはChatGPTを使ってアラートの内容を分析するアクションを実行し、そのあとで `input.called` という配列に `id` が `ask-chatgpt` であるアクションが実行された場合にはSlackに通知を送るアクションを実行する、という順序の制御が行われています。

## 集約・紐づけのためのアラート間データ連携

## アラート対応処理のテスト

# まとめ
