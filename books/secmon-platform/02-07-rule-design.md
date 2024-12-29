---
title: "📐 アラート検知のためのルール設計"
---

ここまでの説明で、自動的なアラートはルールに基づいて検知されることを説明しました。では、実際にどのようなルールを設計すればよいのでしょうか？ 既存のセキュリティ監視システムに触れたことがある人には馴染みがあるかもしれませんが、経験がない場合は想像しにくいかもしれません。今回は、アラート検知のためのルール設計について詳しく説明します。

# アラート検知の考え方

セキュリティ監視におけるアラートの検知の考え方は、大きく分けて3つのパターンがあります。基本的にルールとして定義されるのは以下のいずれかのパターンに属します。これはセキュリティ監視基盤だけでなく、セキュリティ対策ソフトウェア・サービス全般で共通の考え方です。

## (1) 特定の攻撃や侵入活動を検知する

悪意ある活動そのものの痕跡を検知するパターンです。例えば、特定の攻撃コードを含むリクエストや、マルウェアのシグネチャを含むファイルを検知することです。「攻撃者が攻撃に使う手法」がわかっている前提で、その手法を使う過程で発生する痕跡を検知するという考え方です。

最も明確なルールは、攻撃コードやマルウェアのシグネチャのように明確で決定性の高い痕跡を完全一致でマッチングするものです。しかし、このような痕跡は攻撃者が容易に変更でき、検知の見逃し（False Positive）が発生する可能性が高いです。これを防ぐ方法として、痕跡の情報を蓄積し、ルールを更新していくアプローチがあります。アンチウィルス製品のパターンファイル更新はこのアプローチです。しかし、新しい痕跡が次々に発生する環境では、完全に追随するのは難しいでしょう。

そこで、別のアプローチとして攻撃の手順を抽象化し、その手順に合致する一連の痕跡を検知する方法があります。いわゆる「振る舞い検知」がこのアプローチの一つとして知られています。「手順」は様々な粒度で定義できます。例えば、特定のユーザが特定のファイルにアクセスするという単純なものから、特定のユーザが特定のファイルにアクセスし、そのファイルを特定の外部サーバにアップロードするという複雑なものまで様々です。このアプローチは具体的な痕跡に依存しないため、攻撃者が多少細部を変更しても検知できる可能性が高いです。しかし、誤検知（False Positive）が発生しやすいという問題があります。抽象化した際の条件が緩いほど、誤検知が発生しやすくなります。

![](https://storage.googleapis.com/zenn-user-upload/8f780b1039a9-20241116.jpg)

このパターンにおける具体的な検知ルールと抽象的な検知ルールは、どちらが正解ということはなく、環境や目的に応じて使い分ける必要があります。ただ、どちらも攻撃者の手法についての情報収集をしながらルールを調整する必要があります。これは運用上かなりコストがかかることであり、自組織のみで継続的に取り組むためには相応の体制が必要です。「セキュリティ監視基盤で利用するデータ（アラート編）」で紹介した既存のセキュリティ対策ソフトウェア・サービスによるアラートのみを利用するというのも、選択肢の一つです。

## (2) 正常系を定義してその逸脱を検知する

攻撃そのものの痕跡を追うのではなく、自組織で定められたポリシーやシステムの構成を鑑みて「正常とされる」挙動を定義し、その逸脱を検知するパターンもあります。例えば、特定のユーザが特定のリソースにアクセスすることがあるが、そのアクセスが特定の時間帯に発生するというようなものです。この場合、その時間帯以外でそのリソースへのアクセスがあったことを検知することで、攻撃の可能性を捉えることができます。このパターンは攻撃の手法に依存しないため、検知精度が攻撃者に依存しにくいという特徴があります。

このパターンの検知ルールは組織のポリシーなどに強く依存するため、既存のセキュリティ対策ソフトウェア・サービスを提供するベンダがカバーしにくい領域です。そのため、自組織で運用するセキュリティ監視基盤での検知に適したアプローチであると言えます。

攻撃者の手法が変わっても影響されにくいのが特徴ですが、いくつかの課題があります。

- **例外の発生**: 組織内でポリシーとして定められている挙動が、実際には例外によって逸脱することもあります。例えば、緊急時対応では特別な状況下で適切な人の承認を得たうえで、ポリシーから逸脱するような対処をする場合があります。具体的な例としては、障害対応で通常アクセスが禁止されているDBに接続することなどがあります。これは1度きりの対応の場合もあれば、数日〜数週間継続する場合も考えられます。
- **正常系の考慮漏れ**: このパターンでは組織のポリシーに基づいてルールを作ると説明しましたが、組織全体の方針ではなく末端の業務フローに基づくルールとなると詳細の把握は簡単ではありません。把握していない挙動によって誤検知が発生することがあり、最初からすべての挙動を把握することは困難です。
- **業務の変更**: もともとすべての業務を正しく把握していたとしても、業務は既存のものが改定されたり、新しい業務が発生したりします。業務変更後に即時ルールを対応しなくてもいいかもしれませんが、継続的に改善していく必要があります。

これらのことから、正常系を定義して検知ルールに応用する考え方自体は良いのですが、頻繁にルールを更新できる仕組みが必要です。

### ポリシーが決まっているのであれば、システム上制限をかけるべきではないか？

このようなポリシーがあらかじめ決まっている場合、そもそもそのポリシーに違反できないような制限をかけるべきです。しかし、いくつかの理由により監視もしくは検知が必要な場合があります。

- **システム上制限がかけられない**: 利用しているシステムの機能的な制約から、ポリシーに違反する挙動を完全に防ぐことができない場合があります。例えば、アクセス制限の設定粒度が粗いシステムであったり、複雑な要件が求められてシステム側で対応できないなどのケースが考えられます。このような場合に、暫定的な処置としてポリシー上禁止し、それが遵守されているかどうかは監視で確認するというアプローチが取られることがあります。
- **システム上の設定が誤っている、あるいは意図せず変更されている**: 運用している人は適切に制限をかけたつもりでも、誤って設定を変更してしまったり、なんらかの副作用で意図せず変更されてしまったりすることがあります。このような事態を想定して、制限と監視の二段構えで対応することで、より重要なデータを保護するというアプローチがありえます。

このように、監視によってより安全にシステムを運用するという考え方もあります。ただし、すべてを監視と二重に運用するのは効率が悪いため、重要なデータに対してのみ適用を検討するなどの工夫が必要です。

## (3) 統計的手法によって異常を検知する

最後に、統計的手法によって異常を検知するパターンがあります。このパターンは、主に正常系を定義するのが難しい場合に使われます。例えば、特定のリソースへのアクセス回数が通常と比べて突出している場合、あるいは特定のユーザが特定のリソースにアクセスする頻度が通常と比べて突出している場合などです。

このパターンも具体的な攻撃の痕跡に依存しないので、攻撃者の具体的な手法の変更による検知への影響は少ないのですが、一方で誤検知が発生しやすいという問題があります。わかりやすい例として特定のリソースへの突出したアクセスがあった場合、それが攻撃者によって何かしらの調査やDoS攻撃をしているものである可能性もありますが、正常な業務の一環である可能性もあります。なんらかの要因でアクセスが集中するような状況が急遽発生した場合もアラートとして扱われ、結果として誤検知となります。もしアクセスが集中しうるということがわかるとしてもそれはヒューリスティックな情報であり、それならば正常系としてのしきい値を定めて運用するほうが検知された理由も明確で使いやすいでしょう。

根本的な課題として、統計的な異常が検出されたとしてもセキュリティに直接関与するようなアラートはその中の一部しかない、という点になります。そのためこのパターンを使う場合は、他のパターン以上に誤検知が発生しやすいことを前提とすることが重要です。この観点から、監視するべき対象を狭めるなどの工夫が必要です。

# アラート検知ルールの基本形

それでは具体的なルールをどのように書いていくのかを見ていきましょう。ここでは、説明をわかりやすくするためにHTTPアクセスログを例にして考えてみます。HTTPアクセスログはWebサーバなどで生成されるログで、リクエストの内容やレスポンスのステータスコードなどが記録されている想定です。今回は簡略化したクエリにしていますが、実際に使われるクエリも基本形は同じです。

```sql
CREATE TABLE http_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    method TEXT NOT NULL,
    status_code INTEGER NOT NULL,
    url TEXT NOT NULL,
    query TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    auth_user TEXT,
    remote_addr TEXT NOT NULL
);
```

今回は先程説明した3つのパターンのうち、(1)特定の攻撃や侵入活動を検知する、(2)正常系を定義してその逸脱を検知する、の2つについて具体的なルールを考えてみます。統計的手法による異常検知については、実践的なルールの紹介が難しいので今回は割愛します[^anomaly]。

[^anomaly]: 本書で利用する予定のBigQueryには異常検知の機能が用意されているため、興味のある方はそちらを参照してみてください。 https://cloud.google.com/bigquery/docs/anomaly-detection-overview?hl=ja

ルール検知は1時間に一度クエリを発行して検査するという前提で考えます。この前提は、リアルタイムでの検知が必要な場合はストリーム処理を使うなどの工夫が必要ですが、ここでは簡単のためにバッチ処理で検知することとします。（検知におけるストリーム処理とバッチ処理の違いについては、別の章で説明します）1時間に一度の検査ということから、直近1時間のログを取得するようにクエリを書く必要があります。

## 単純一致検索

最も単純なルールはログ単位の一致検索です。例えば攻撃を検知するというルールとして、（SQL Injectionの可能性がある）Query Stringに`SELECT`が含まれるリクエストを検知するクエリは以下のように書けます。

```sql
SELECT *
FROM http_logs
WHERE
    query LIKE '%SELECT%'
    AND timestamp > datetime('now', '-1 hour');
```

このクエリは、`http_logs`テーブルから`query`カラムに`SELECT`が含まれる、直近1時間のデータを取得します。非常に単純な記述ですが、これもルールの一つになります。また、正常系を定義してその逸脱を検知するルールとして、特定のユーザが特定のリソースにアクセスするというルールは以下のように書けます。

```sql
SELECT *
FROM http_logs
WHERE
    auth_user = 'alice'
    AND url = '/admin'
    AND timestamp > datetime('now', '-1 hour');
```

このクエリは、`http_logs`テーブルから`auth_user`カラムが`alice`で、`url`カラムが`/admin`である、直近1時間のデータを取得します。このように単純な一致検索は簡単に書ける反面、検査する対象が一つのログに閉じてしまうため、条件として使える情報が限られてしまいます。より複雑な条件を書くためには、複数のログやデータを利用する必要があります。

## 相関分析

複数のログ、データを突合して検知するルールを相関分析[^correlation]と呼ぶことがあります。異なるシステムからのデータを組み合わせることで、横断的に事象を観測したり、より複雑な条件を書くことができます。これがセキュリティ監視基盤にログを集約する大きなメリットの一つです。

[^correlation]: 本来、相関分析という言葉はデータ分析の分野で使われる2つ以上の変数間の関係を調べる手法を指しますが、SIEM関連では複数のログデータを突合して検知するルールを指しています。

### IoCの利用

異なるデータを突合して検知するルールもあります。例えば、アクセスしてきたIPアドレスがIoC（Indicator of Compromise）に含まれていた場合は不審なアクセスとみなすことができます。例として以下のようなテーブルが別途あったとします。

```sql
CREATE TABLE ioc (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_addr TEXT NOT NULL,
    src TEXT NOT NULL
);
```

このテーブルは何らかの方法でIoC情報が登録されているとします。このテーブルを使って、アクセスしてきたIPアドレスがIoCに含まれているかどうかを検知するクエリは以下のように書けます。

```sql
SELECT *
FROM http_logs
WHERE
    remote_addr IN (
        SELECT ip_addr
        FROM ioc
    )
    AND timestamp > datetime('now', '-1 hour');
```

このクエリは、`http_logs`テーブルから`remote_addr`カラムが`ioc`テーブルの`ip_addr`カラムに含まれる、直近1時間のデータを取得します。このように別データとの突合を行うことで、より複雑な条件を書くことができます。

### 別ログデータとの突合

別のログデータとの突合も有効なルールの一つです。例えば、組織内のユーザが利用しているモバイルデバイスのログと、HTTPアクセスログを突合して、モバイルデバイスからのアクセスで認証されていないリソースにアクセスしている場合を検知するというルールが考えられます。例として以下のようなテーブルが別途あったとします。

```sql
CREATE TABLE mobile_device_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    device_name TEXT NOT NULL,
    user TEXT NOT NULL,
    ip_addr TEXT NOT NULL
);
```

このテーブルはモバイルデバイスのログとして、デバイス名、ユーザ名、IPアドレスなどが記録されているとします。このテーブルを使って、1時間以内のモバイルデバイスのログとHTTPアクセスログを突合して、モバイルデバイスからの不審なアクセスを検知するクエリは以下のように書けます。

```sql
SELECT h.*
FROM http_logs AS h
JOIN mobile_device_logs AS m ON h.auth_user = m.user
WHERE h.timestamp >= DATETIME('now', '-1 hour')
  AND m.timestamp >= DATETIME('now', '-1 hour')
  AND h.remote_addr NOT IN (
      SELECT ip_addr
      FROM mobile_device_logs
      WHERE user = h.auth_user
        AND timestamp >= DATETIME('now', '-1 hour')
  );
```

このクエリは、`http_logs`テーブルと`mobile_device_logs`テーブルを突合して、モバイルデバイスが利用していると記録されていないIPアドレスからのアクセスを、直近1時間のデータから取得します。このように別データとの突合を行うことで、より複雑な条件を書くことができます。

## 期間集計

一定期間に発生したログを集計した結果に基づいて、アラートとして検知するというルールも有効です。例えば、一定期間における特定のユーザが特定のリソースにアクセスする頻度が通常と比べて突出していることを検知する、というようなルールです。これは例えば内部の人間が悪意を持って情報を持ち出そうとしている可能性があるといった場合に有効です。こういったアクセス件数をベースにしたようなチェックは一定期間ごとに人間が目視で確認するというような運用が行われることが多いですが、ルールとして記述することで自動化することも可能です。

SQLでシンプルに記述しようとするならば、`GROUP BY`句を使って期間集計を行うことができます。例として、直近1時間におけるユーザごとのアクセス回数を集計して、通常と比べて突出しているユーザを検知するクエリは以下のように書けます。

```sql
SELECT auth_user, COUNT(*) AS cnt
FROM http_logs
WHERE timestamp >= DATETIME('now', '-1 hour')
GROUP BY auth_user
HAVING cnt > 100;
```

このクエリは、`http_logs`テーブルから直近1時間のデータを取得し、ユーザごとにアクセス回数を集計して、アクセス回数が100回を超えるユーザを取得します。このように期間集計を行うことで、一定期間におけるアクセス回数などを検知することができます。このしきい値は、運用している環境に合わせて調整する必要がありますし、複数の条件を組み合わせることでより精緻な検知を行うことができます。

## 状態遷移

相関分析からもう一段階進んだルールとして、状態遷移を利用した検知があります。状態遷移とは、ある状態から別の状態に遷移するというような事象を検知するルールです。例えば、特定のユーザが特定のリソースAにアクセスした後、異なるリソースBへのアクセスがあった場合を検知する、というようなルールです。これは攻撃者の行動をモデル化することで、1つずつは正常なアクセスであっても、複数のアクセスを組み合わせて異常を検知するというアプローチです。

このアプローチは明確に攻撃を示していないログからも侵害の兆候を検出できるというメリットがありますが、その分False positive, False negativeの両方の誤検知が発生しやすいというデメリットもあります。また、攻撃者の行動をモデル化し、状態遷移を利用したルールをメンテナンスしていくのも容易ではないため、運用コストが高いという問題もあります。

SQLで状態遷移を利用した検知を行うためには、`LAG`関数を使って前のログとの比較を行うことができます。例として、直近1時間において特定のユーザが特定のリソースAにアクセスした後、異なるリソースBへのアクセスがあった場合を検知するクエリは以下のように書けます。

```sql
WITH user_access AS (
    SELECT
        auth_user,
        url,
        LAG(url) OVER (PARTITION BY auth_user ORDER BY timestamp) AS prev_url
    FROM http_logs
    WHERE timestamp >= DATETIME('now', '-1 hour')
)
```

ただし、実際には状態遷移の条件となるログの範囲を広く取ったり、状態遷移をパターンが複雑化したりすることが多いため、SQLだけで完結することは難しいです。そのため実践的には、対象となるログデータをまとめて取得した後、個別に実装したプログラムに入力して検知するというアプローチになるでしょう。

# まとめ

アラート検知のためのルール設計について、3つのパターンを紹介しました。これらのパターンは、セキュリティ監視基盤を構築する際には必ずしも独立して使われるものではなく、組み合わせて使うことでより効果的な検知が可能になります。また、それぞれのパターンには誤検知が発生しやすくなる問題がありますが、それを踏まえた上でルールを設計し、運用を行うことが重要です。