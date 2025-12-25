---
title: "構造化データ出力でIoCなど属性値を抽出する"
---

本章はLLMにテキストを作成させる際、構造化データ（主にJSON形式）を出力させる方法について解説します。今回のコードは https://github.com/m-mizutani/leveret の [day06-structured-output](https://github.com/m-mizutani/leveret/tree/day06-structured-output) ブランチに格納されていますので適宜参照してください。

# なぜ構造化データの出力が必要か

前章ではアラートのタイトルと要約を個別にテキストで自動生成する方法を実装しました。しかし、この方法にはいくつかの問題があります。

まず、複数項目についてテキストを取得したい場合、API呼び出し回数が増えてしまいます。LLMサービスのAPI呼び出しは一般的に数秒かかるため、呼び出し回数が増えるほど全体のレイテンシに影響します。並列実行も可能ですが、LLMサービスのrate limitに引っかかる可能性があるため、むやみに並列度を上げることもできません。

また、構造化されたデータの取得には適していません。たとえば本章で実装するIoC（Indicator of Compromise：侵害指標）情報のように、IPアドレス・ドメイン・ハッシュといった複数のデータが関係性を保ちながら存在する場合、個別に取得すると対応関係が失われてしまいます。同じアラートから複数の同じ形式のデータを抽出したい場合も、テキスト形式では扱いにくくなります。

このような問題を解決するため、一度のAPI呼び出しで複雑な関係性を持つ構造化データを取得する仕組みが必要です。これによってリクエストの往復回数が減り、関係性のあるフィールドや繰り返し登場する同じ形式のデータを効率的に抽出できます。

# 応答形式の指定

Gemini APIでは、生成する応答の形式を制御するために `ResponseMIMEType` と `ResponseSchema` という2つのパラメータを指定できます。

`ResponseMIMEType` は応答の形式を指定します。今回はJSON形式で構造化データを取得したいため `application/json` を指定します。`ResponseSchema` は[JSON Schema](https://json-schema.org/)ライクな形式でスキーマを指定できます。これによって、出力されるJSONの構造を期待する形に制約できます。この2つのパラメータを組み合わせることで、LLMに構造化されたデータを出力させることができます。

なお、スキーマだけでなくプロンプト内でもスキーマ構造の説明やサンプルを追加しておくと、より期待した回答が得られやすくなります。スキーマは形式の制約を提供し、プロンプトは意味的な指示を提供するという役割分担です。

まず前章で実装したタイトルと要約の作成を構造化出力に書き換えてみます。以下のようにスキーマを定義します。

```go:pkg/usecase/alert/insert.go
config := &genai.GenerateContentConfig{
    ResponseMIMEType: "application/json",
    ResponseSchema: &genai.Schema{
        Type: genai.TypeObject,
        Properties: map[string]*genai.Schema{
            "title": {
                Type:        genai.TypeString,
                Description: "Short title for the alert",
				MaxLength:   &maxLen,
            },
            "description": {
                Type:        genai.TypeString,
                Description: "Detailed description (2-3 sentences) for the alert",
            },
        },
        Required: []string{"title", "description"},
    },
}
```

このスキーマでは `title` と `description` という2つのプロパティを定義しています。両方とも `Required` 配列に含めることで必須フィールドとして指定しています。`title` フィールドには `MaxLength` で最大文字数を制約しています。ただし、マルチバイト文字がどう処理されるかは実装依存な部分があるため、後述するようにアプリケーション側でも検証を行います。

次に、この応答を受け取るためのGo構造体を定義します。バリデーションの大部分はスキーマに表現できていますが、念のため手元でも検証できるようにしておきます。前章と同様にリトライ処理を実装するため、`validate` メソッドを用意します。

```go:pkg/usecase/alert/insert.go
type alertSummary struct {
	Title       string `json:"title"`
	Description string `json:"description"`
}

func (s *alertSummary) validate() error {
	if len(s.Title) > maxTitleLength {
		return goerr.New("title too long", goerr.V("title", s.Title), goerr.V("length", len(s.Title)), goerr.V("maxLength", maxTitleLength))
	}
	if s.Title == "" {
		return goerr.New("title is empty")
	}
	if s.Description == "" {
		return goerr.New("description is empty")
	}
	return nil
}
```

プロンプトも構造化出力に合わせて更新します。前章では `title.md` と `description.md` を個別に用意していましたが、今回はこれらを統合して `summary.md` というひとつのプロンプトファイルにします。内容が複雑になってきたため、markdownの見出しで章分けして説明することで、LLMが要件を理解しやすくなります。

```md
Generate a JSON response with a short title and detailed description for this security alert.

# Requirements:
- title: Must be less than {{.MaxTitleLength}} characters
- description: Should be 2-3 sentences explaining what happened and why it might be important

# Alert data:
{{.AlertData}}
{{- if .FailedExamples}}

# Previous attempts failed with the following errors:
{{- range .FailedExamples}}
- {{.}}
{{- end}}
{{- end}}

Return the response as JSON with "title" and "description" fields.
```

このプロンプトは3つのセクションで構成されています。`Requirements` セクションでは出力データの制約を明示し、`Alert data` セクションでは分析対象のアラート情報を渡します。`Previous attempts failed` セクションはリトライ時にのみ表示され、前回失敗した理由をLLMにフィードバックします。

スキーマとプロンプトの準備ができたら、先ほど定義した `config` を指定して生成AIへプロンプトを送信します。返り値はあくまでテキスト形式のJSON文字列なので、`json.Unmarshal` で構造体に復元します。前章同様、バリデーションに失敗した場合はリトライを行います。以下のコードは最大3回までリトライするループ内に配置されます。`validate()` でエラーが出た場合はそのエラーメッセージを `FailedExamples` に追加し、プロンプトを再生成して送信することで、LLMが前回の失敗から学習できるようにします。

```go
resp, err := gemini.GenerateContent(ctx, contents, config)
if err != nil {
  return nil, goerr.Wrap(err, "failed to generate content for summary")
}

if resp == nil || len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil || len(resp.Candidates[0].Content.Parts) == 0 {
  return nil, goerr.New("invalid response structure from gemini", goerr.V("resp", resp))
}

// DEBUG: remove me later
rawJSON := resp.Candidates[0].Content.Parts[0].Text
fmt.Printf("[DEBUG] received JSON from Gemini: %s\n", rawJSON)

var summary alertSummary
if err := json.Unmarshal([]byte(rawJSON), &summary); err != nil {
  return nil, goerr.Wrap(err, "failed to unmarshal summary JSON", goerr.V("text", rawJSON))
}

if err := summary.validate(); err != nil {
  logger.Warn("validation failed, retrying", "error", err, "title", summary.Title)
  failedExamples = append(failedExamples, err.Error())
  continue
}
```

実際に実行してみると、一度のリクエストでtitleとdescriptionの両方が取得できていることがわかります。前章では2回のAPI呼び出しが必要でしたが、構造化出力を使うことで1回の呼び出しで完結します。今回はLLMから返されたJSON文字列がどのような形式になっているか確認するため、デバッグ用の `Printf` で出力しています。

```shell
$ go run . new -i examples/alert/guardduty.json
[DEBUG] received JSON from Gemini: {"title": "EC2 instance querying malware drop point domain", "description": "An EC2 instance, i-99999999, has been observed querying the domain '3322.org', which is identified as a malware drop point. This domain is known to be used for collecting stolen credentials and other sensitive data, indicating a potential compromise of the instance that requires urgent investigation."}
Alert created: 84d390fb-1421-4d40-afae-84176ab10e6b
```

# IoC（IP、ドメイン、ハッシュ）の抽出実装

構造化出力の基本を理解したところで、次はより実践的な例としてIoC情報の抽出を実装します。

## IoCとは

IoC（Indicator of Compromise：侵害指標）とは、システムへの不正アクセスや侵害が発生した可能性を示す証拠のことです。具体的にはIPアドレス、ドメイン名、ファイルハッシュ、URLなどが該当します。

たとえば、あるマルウェアに感染したサーバが特定のIPアドレス `192.0.2.100` に通信していた場合、このIPアドレスがIoCとなります。同じIPアドレスへの通信が他のサーバでも検出されれば、それらも同じマルウェアに感染している可能性が高いと判断できます。同様に、不正なドメイン名への問い合わせや、既知のマルウェアのファイルハッシュが見つかった場合も、侵害の証拠として扱われます。

IoCを抽出することで、単一のアラートだけでなく組織全体での影響範囲を迅速に調査できます。また、抽出したIoCを脅威インテリジェンスサービスに問い合わせることで、攻撃者の意図や攻撃手法についての追加情報を得ることもできます。このように、IoCはセキュリティインシデント対応における重要な手がかりとなります。

## なぜ抽出するか

アラートが構造化データであれば、IoC情報はその中に含まれているため、構造データのパスなどを指定してそのまま取り出せばよいと考えるかもしれません。しかし実際のセキュリティ運用では、数百種類ものアラートが存在し、それぞれ異なるスキーマを持っています。全てのアラートスキーマを管理し、個別に抽出ロジックを実装するのは現実的ではありません。

決定性が求められるものや特に重要なものは自前で抽出ロジックを書くべきですが、「大まかにIoC情報を抽出したい」というタスクにはLLMが適しています。生成AIはアラートの内容を理解し、柔軟にIoC情報を識別できるため、スキーマの多様性に対応しやすくなります。

## 実装

### Attributeの設計

まずIoC情報やその他の属性情報を格納するための構造体を定義します。`Attribute` 構造体は `Key`、`Value`、`Type` の3つのフィールドを持ちます。`Type` は事前に定義された `AttributeType` 型で、IPアドレス、ドメイン、ハッシュなどの属性の種類を表します。この構造体もスキーマである程度制約できますが、生成AI以外の入力経路でも後日使用するため、`Validate` メソッドを用意しておきます。

```go:pkg/model/alert.go
type AttributeType string

const (
	AttributeTypeString    AttributeType = "string"
	AttributeTypeNumber    AttributeType = "number"
	AttributeTypeIPAddress AttributeType = "ip_address"
	AttributeTypeDomain    AttributeType = "domain"
	AttributeTypeHash      AttributeType = "hash"
	AttributeTypeURL       AttributeType = "url"
)

type Attribute struct {
	Key   string        `json:"key"`
	Value string        `json:"value"`
	Type  AttributeType `json:"type"`
}

// Validate checks if the attribute is valid
func (a *Attribute) Validate() error {
	if a.Key == "" {
		return goerr.New("attribute key is empty")
	}
	if a.Value == "" {
		return goerr.New("attribute value is empty")
	}
	switch a.Type {
	case AttributeTypeNumber, AttributeTypeIPAddress, AttributeTypeDomain, AttributeTypeHash, AttributeTypeURL, AttributeTypeString:
		return nil
	default:
		return goerr.New("invalid attribute type", goerr.V("type", a.Type))
	}
}
```

次に、前章で定義した `alertSummary` 構造体に `Attributes` フィールドを追加します。また、`Attributes` のバリデーションも追加しておきます。

```go:pkg/usecase/insert.go
type alertSummary struct {
	Title       string             `json:"title"`
	Description string             `json:"description"`
	Attributes  []*model.Attribute `json:"attributes"`
}

func (s *alertSummary) validate() error {
	if len(s.Title) > maxTitleLength {
		return goerr.New("title too long", goerr.V("title", s.Title), goerr.V("length", len(s.Title)), goerr.V("maxLength", maxTitleLength))
	}
	if s.Title == "" {
		return goerr.New("title is empty")
	}
	if s.Description == "" {
		return goerr.New("description is empty")
	}
	for _, attr := range s.Attributes {
		if err := attr.Validate(); err != nil {
			return goerr.Wrap(err, "invalid attribute")
		}
	}
	return nil
}
```

### Response Schemaの更新

構造体の定義ができたら、Response Schemaを更新します。先ほどの `title` と `description` に加えて、`attributes` という配列とその中身のスキーマを定義します。今回はわかりやすさのため `config` 内に直接記述していますが、メンテナンス性を考慮する場合は別の設計も考えられます。たとえば、`Attribute` 構造体から自動的にスキーマを生成する関数を model 層に用意すれば、構造体定義とスキーマ定義の二重管理を避けられます。

スキーマでは `key`、`value`、`type` の各フィールドについて詳しい説明を追加しています。特に `type` フィールドは `Enum` で `"number"`、`"ip_address"`、`"domain"`、`"hash"`、`"url"`、`"string"` の6種類に制約しています。

```go:pkg/usecase/insert.go
		config := &genai.GenerateContentConfig{
			ResponseMIMEType: "application/json",
			ResponseSchema: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"title": {
						Type:        genai.TypeString,
						Description: "Short title for the alert",
						MaxLength:   &maxLen,
					},
					"description": {
						Type:        genai.TypeString,
						Description: "Detailed description (2-3 sentences) for the alert",
					},
					"attributes": {
						Type:        genai.TypeArray,
						Description: "Most critical attributes essential for investigation: IOCs and key contextual information only",
						Items: &genai.Schema{
							Type: genai.TypeObject,
							Properties: map[string]*genai.Schema{
								"key": {
									Type:        genai.TypeString,
									Description: "Attribute name in snake_case (e.g., 'source_ip', 'user_name', 'error_count')",
								},
								"value": {
									Type:        genai.TypeString,
									Description: "Attribute value as a string",
								},
								"type": {
									Type:        genai.TypeString,
									Description: "Most specific attribute type: 'ip_address', 'domain', 'hash', 'url', 'number', or 'string' for general text",
									Enum:        []string{"string", "number", "ip_address", "domain", "hash", "url"},
								},
							},
							Required: []string{"key", "value", "type"},
						},
					},
				},
				Required: []string{"title", "description", "attributes"},
			},
		}
```

### データの抽出、バリデーション、格納

スキーマを定義したら、LLMから返されたJSONを構造体にアンマーシャルし、バリデーションを実行します。今回は構造化データの内容を確認しやすくするため、Pretty Printを行っています。

```go
		var summary alertSummary
		if err := json.Unmarshal([]byte(rawJSON), &summary); err != nil {
			return nil, goerr.Wrap(err, "failed to unmarshal summary JSON", goerr.V("text", rawJSON))
		}

		// [DEBUG] Pretty print the parsed JSON
		if prettyJSON, err := json.MarshalIndent(summary, "", "  "); err == nil {
			fmt.Printf("parsed summary JSON: %s\n", string(prettyJSON))
		}

		if err := summary.validate(); err != nil {
			logger.Warn("validation failed, retrying", "error", err, "title", summary.Title)
			failedExamples = append(failedExamples, err.Error())
			continue
		}
```

バリデーションが成功したら、`generateSummary` の呼び出し後、取得したデータを `alert` 構造体に格納します。`Title` と `Description` に加えて、今回新たに追加した `Attributes` も保存します。

```go
	summary, err := generateSummary(ctx, u.gemini, string(jsonData))
	if err != nil {
		return nil, goerr.Wrap(err, "failed to generate summary")
	}
	alert.Title = summary.Title
	alert.Description = summary.Description
	alert.Attributes = summary.Attributes
```

### 実行結果

実装が完了したので、実際に実行してみます。

```bash
$ go run . new -i examples/alert/guardduty.json
parsed summary JSON: {
  "title": "EC2 Instance Querying Malware Drop Point Domain",
  "description": "An EC2 instance has been observed querying a domain, \"3322.org\", known to be a drop point for malware-collected credentials and stolen data. This activity suggests a potential compromise of the EC2 instance, indicating it might be infected or involved in data exfiltration. Immediate investigation is required to determine the scope and impact of this potential breach.",
  "attributes": [
    {
      "key": "detected_domain",
      "value": "3322.org",
      "type": "domain"
    },
    {
      "key": "instance_id",
      "value": "i-11111111",
      "type": "string"
    },
    {
      "key": "aws_account_id",
      "value": "783957204773",
      "type": "string"
    },
    {
      "key": "aws_region",
      "value": "ap-northeast-1",
      "type": "string"
    },
    {
      "key": "instance_public_ip",
      "value": "198.51.100.0",
      "type": "ip_address"
    },
    {
      "key": "instance_private_ip",
      "value": "192.168.0.1",
      "type": "ip_address"
    },
    {
      "key": "severity_score",
      "value": "8",
      "type": "number"
    },
    {
      "key": "finding_type",
      "value": "Trojan:EC2/DropPoint!DNS",
      "type": "string"
    }
  ]
}
```

このように、生成AIは `attributes` 配列に複数のIoC情報と重要な属性を抽出してくれます。`detected_domain` は `domain` 型として、`instance_public_ip` は `ip_address` 型として正しく分類されています。また、AWSアカウントIDやリージョンといった調査に必要な情報も併せて抽出されています。

## 抽出の過不足について

実行結果を見て、抽出された属性が多いと感じた人もいれば、少ないと感じた人もいるかもしれません。これはLLMへの指示によって調整できます。プロンプトを厳しくすれば抽出数は減り、ゆるくすれば増えます。

しかし、この結果の「適切さ」を人間の感覚と完全に一致させるのは困難です。実際のところ、人間同士でも何を抽出すべきかという認識を揃えるのは難しいものです。どの程度の粒度で属性を抽出するかは、組織の運用方針や分析者の好みに依存します。プロンプトによる調整方法については後日詳しく扱います。

# まとめ

本章はLLMから構造化データを出力させる方法について実装しました。

`ResponseMIMEType` と `ResponseSchema` を組み合わせることで、LLMに期待する形式のJSONを出力させることができます。単純なテキスト生成と比べて、複数のフィールドを一度に取得でき、配列のような繰り返しデータも扱えます。また、スキーマで型や必須フィールドを制約することで、ある程度の品質を保証できます。

今回実装したIoC抽出機能は、アラートスキーマの多様性に対応する実用的な例です。数百種類のアラートに対して個別に抽出ロジックを書く代わりに、LLMが柔軟にIoC情報を識別してくれます。ただし、抽出結果の粒度は人間の感覚と完全に一致させることは難しく、プロンプト調整が必要になることを理解しておく必要があります。

次章では、LLMの出力品質を向上させるプロンプトチューニングの技術について解説します。
