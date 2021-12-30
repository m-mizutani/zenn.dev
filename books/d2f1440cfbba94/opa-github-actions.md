---
title: "GitHub Action で Trivy + OPA/Rego による脆弱性管理"
---


今回は GitHub Actions で [Trivy](https://aquasecurity.github.io/trivy) を用いてOSSパッケージの脆弱性検査をした際に、カスタムポリシーによってCIを落とすような仕組みについて紹介[^octovy]します。

もともとコンテナイメージの脆弱性スキャナとして開発されていたTrivyですが、最近は[ファイルシステムにあるパッケージシステムの脆弱性をスキャンする機能](https://github.com/aquasecurity/trivy/releases/tag/v0.9.0)も実装されています。この機能を利用した[GitHub Actions](https://github.com/aquasecurity/trivy-action)も提供されており、自分が開発してるリポジトリで利用している外部パッケージにどのような脆弱性が含まれているかを簡単に調べることができるようになっています。

またTrivy自体のオプションも多彩で、終了時に異常終了（exit codeが非ゼロ）しGitHub Actionsを失敗させ、CIを止めることもできます。例えば一定以下のSeverityしかない場合や、修正バージョンが提供されていない場合にはこれを無視してCIを通す、というような制御もできます。

しかし実際の運用だと、よりきめ細かく制御をしたい場合もあります。例えば複数の条件が満たされたときは無視する、あるいはCIを落とすといった「かゆいところに手が届く」判定をしたい場合というのがあります。そこで今回はTrivyから出力された結果をOPAに入力し、Regoで記述されたポリシーでCIの成功・失敗を判定させる[^official]という方法を紹介したいと思います。

# 構成

まずはCI設定の構成から紹介します。サンプルのコードは以下のリポジトリにあります。
https://github.com/m-mizutani/trivy-opa-example

GitHub Actions の [workflowファイル](https://github.com/m-mizutani/trivy-opa-example/blob/main/.github/workflows/trivy.yml) は以下のようになります。

```yml
name: Vuln scan

on: [push]

jobs:
  scan:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout upstream repo
        uses: actions/checkout@v2
        with:
          ref: ${{ github.head_ref }}
      - name: Run Trivy vulnerability scanner in repo mode
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          format: json
          output: trivy-results.json
      - uses: docker://openpolicyagent/opa:0.34.2-rootless
        with:
          args: "eval -f pretty -b .github/workflows -i trivy-results.json --fail-defined data.vuln.failed"
```

2番目のステップで trivy-action を利用し、リポジトリのコードに対してTrivyのスキャンをかけます。結果をJSON形式で `trivy-results.json` へ書き出します。

その後、3番目のステップで OPA を呼び出します。バイナリイメージをダウンロードして GitHub Actions 内へ展開するという方法もありますが、公式サポートの GitHub Actions はないようなので、今回はコンテナイメージを利用しています。

`args` で指定しているオプションについて説明します。

- `eval`: one shotでポリシーの評価だけをするモードです
- `-f pretty`: 出力フォーマットをprettyにしています。デフォルトの `json` 形式だと評価結果以外にメタ情報も表示するので省略された形式を指定しています
- `-b .github/workflows`: ポリシーがアーカイブされたバンドル、もしくはポリシーが設置されたディレクトリを指定しています。今回は `.github/workflows/vuln.rego` というファイルを置いています
- `-i trivy-results.json`: 一つ前のステップで出力されたTrivyの結果ファイルを `input` として扱います
- `--fail-defined`: 今回は「条件がマッチした場合に異常終了させる」という方針のため、返り値に何かが入っていた場合にfailするというオプションです
- `data.vuln.failed`: 今回のクエリです。`package vuln` 内の `failed` という変数に入れられた値が返ります

この設定を記述した後、 `.github/workflows/vuln.rego` にポリシーを記述します。

# 具体例

ユースケースとともに、具体的なポリシーの記述を見ていきたいと思います。

今回の例では出力結果の見やすさに少し配慮し、やや変則的なルールにしています。

```rego
failed = result {
    count(reasons) > 0
    result = {
        "Result": "Failed by custom policy",
        "Reasons": reasons,
    }
}
```

先述したとおり、 `failed` という変数に値が入っていた場合にCIが失敗するようにしています。上記の例では `reasons` という変数に1つ以上の値が入っていたら `failed` に値（`result`）を代入、そうでなければ何もしない、という動作をします。

これによって、以下のように "Reasons" というフィールドにメッセージを複数表示させて、かつ少しだけ見やすい形式になっています。

![](https://storage.googleapis.com/zenn-user-upload/64fd7740139b-20211130.png)

## 特定の脆弱性が混入した場合にfailさせる

```rego
reasons[msg] {
    src := input.Results[_]
    vuln := src.Vulnerabilities[_]
    vuln.VulnerabilityID == "CVE-2020-8164"
    msg := sprintf("Denied CVE-2020-8164 (%s %s in %s)", [vuln.PkgName, vuln.InstalledVersion, src.Target])
}
```

`CVE-2020-8164` の場合だけCIを失敗させる[^ignore]、という非常にシンプルなパターンですが、出力結果の説明をリッチにするためやや複雑な書き方になっています。もっともシンプルに記述したい場合は以下のようにもできます。

```rego
reasons[msg] {
    input.Results[_].Vulnerabilities[_].VulnerabilityID == "CVE-2020-8164"
    msg := "Denied CVE-2020-8164"
}
```

ユースケースとしては、閉鎖環境などで利用されており、ひとまずはほとんどの脆弱性はそのまま通していいが極めて影響が大きいと考えられる脆弱性だけを厳選したい、というようなシチュエーションが考えられます。複数の脆弱性を対象としたい場合は、以下のような書き方ができます。

```rego
urgentVulns := [
    "CVE-2020-8164",
    "CVE-2018-16476",
]

reasons[msg] {
    src := input.Results[_]
    vuln := src.Vulnerabilities[_]
    vuln.VulnerabilityID == urgentVulns[_]
    msg := sprintf("Denied Urgent %s (%s %s in %s)", [vuln.VulnerabilityID, vuln.PkgName, vuln.InstalledVersion, src.Target])
}
```

## 機密性への影響が大きい脆弱性があったらfailさせる

Trivyの出力結果には脆弱性の種類や影響の規模を示す共通脆弱性評価システムの[CVSS](https://www.ipa.go.jp/security/vuln/CVSS.html)の情報が付与されます。これによって攻撃の実現可能性やどのような影響が考えられるかを一定読み取ることができます[^cvss]。CVSSにはその脆弱性がセキュリティの三大要素である機密性（Confidentiality）、完全性（Integrity）、可用性（Availability）のどこに影響があるのかが示されたフィールドがあります。

もし機密性に重大な影響がある（ `C:H` というフィールドが含まれる）脆弱性のみを検出したい、という場合は以下のようなルールを記述できます。

```rego
reasons[msg] {
    src := input.Results[_]
    vuln := src.Vulnerabilities[_]
    cvss := vuln.CVSS[_]
    "C:H" == split(cvss.V3Vector, "/")[_]

    msg := sprintf("Denied high impact for confidentiality (%s %s in %s)", [vuln.PkgName, vuln.InstalledVersion, src.Target])
}
```

## 特定のパッケージ＆バージョンがあったらfailさせる

最後の例は脆弱性の有無に関わらず、特定のパッケージの特定のバージョンを拒否するようなユースケースです。近年、オープンソースのパッケージを狙ったサプライチェーン攻撃がにわかに増加しつつあります。先日も[coaとrcという広く利用されているパッケージに悪意あるコードが埋め込まれるという事件](https://therecord.media/malware-found-in-coa-and-rc-two-npm-packages-with-23m-weekly-downloads/)がありました。こうした場合、悪意あるコードが混入したバージョンは削除され、後日Trivyなどの脆弱性検査ツールで検出できるようになります。しかし先にコードが混入したという情報だけが伝搬してくることが多く、その時点では脆弱性検査ツールでは検出できません。このような脆弱性は被害が甚大になる可能性があるため、セキュリティ担当者の立場からは一刻も早く対処する必要があります。

Trivyには脆弱性検出だけでなく、スキャンしたパッケージ一覧を出力する `--list-all-pkg` オプションがあります。これによって出力されたパッケージ一覧とアドホックに記述したポリシーによって深刻な影響を及ぼす可能性のある脆弱性のデプロイを水際で止めることができます。

```rego
reasons[msg] {
    src := input.Results[_]
    src.Type == "bundler"
    pkg := src.Packages[_]
    pkg.Name == "thread_safe"
    pkg.Version == "0.3.6"
    msg := sprintf("Denied thread_safe v0.3.6 in %s", [src.Target])
}
```

上記の例は `bundler` (RubyGems) における `thread_safe` というパッケージのバージョン `0.3.6` に深刻な脆弱性が埋め込まれつつ、まだ脆弱性IDなどが割り当てられていないタイミングで適用することを想定したポリシーです。このようなポリシーを自由に記述できるのがOPAのようなポリシーエンジンを使う強みと言えるかと思います。

[^cvss]: 個人的には評価する人や組織によって評価のブレが大きいため、あくまで参考程度にするのが望ましいと考えています
[^ignore]: ちなみに特定の脆弱性だけ無視する、はTrivy単体の機能でも[.trivyignoreを使う](https://aquasecurity.github.io/trivy/v0.21.1/vulnerability/examples/filter/)ことで実現できます
[^official]: TrivyにもRegoによるポリシー記述の機能として `--ignore-policy` オプションが実装されています。ただ、記事執筆時点で最新の[v0.21.1](https://aquasecurity.github.io/trivy/v0.21.1/vulnerability/examples/filter/)でExperimental扱いなのと、Trivy以外のCIにも応用できるように、という狙いで今回は利用しませんでした。
[^octovy]: 筆者は先日、[Trivy + Regoを用いたパッケージ脆弱性管理](https://speakerdeck.com/mizutani/trivy-rego) という内容で似たようなトピックについての講演をしています。この発表では組織横断で管理することを想定していますが、今回の記事ではリポジトリごとに管理するというユースケースを想定しています。