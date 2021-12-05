---
title: "Regoの基礎（サンプル編）"
emoji: "🤖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["opa", "rego"]
published: false
---

この記事は[OPA/Regoアドベントカレンダー](https://adventar.org/calendars/6601)のN日目です。

今回は具体的なユースケースに基づいてRegoの記述例を紹介したいと思います。公式でも[Kubernetes を題材に使用例を紹介](https://www.openpolicyagent.org/docs/latest/kubernetes-primer/)しているので、あわせてご参照ください。

## Trivy

## AWS CloudWatch Event

```rego
package aws

allowed_registries = [
    "111111111.dkr.ecr.us-west-2.amazonaws.com/",
    "222222222.dkr.ecr.us-west-2.amazonaws.com/",
    "111111111.dkr.ecr.ap-northeast-1.amazonaws.com/",
]

deployed_unexpected_image[msg] {
    input.source == "aws.ecs"
    container := input.detail.containers[_]
    count({x | startswith(container.image, allowed_registries[x])}) == 0
    msg := sprintf("Deployed unexpected image %s", [container.containerArn])
}
```

## AWS EC2

```rego
package aws

exposed_allow_list := [
    "i-00000000000000000",
    "i-11111111111111111",
    "i-22222222222222222",
]

exposed_instances[id] {
    instance := input.Reservations[_].Instances[_]
    not instance.PublicIpAddress == ""
    not net.cidr_contains("10.0.0.0/8", instance.PublicIpAddress)
    count({x | exposed_allow_list[x] == instance.InstanceId}) == 0
    id := instance.InstanceId
}
```
