---
title: "実践セキュリティ監視基盤構築(17):  ログ書込"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

この記事はアドベントカレンダー[実践セキュリティ監視基盤構築](https://adventar.org/calendars/9986)の17日目です。

今回はデータウェアハウスにおけるETL（Extract, Transform, Load）のうち、ログの書き込み（Load）について紹介します。ログの書き込みは、ログの変換までの処理を終えたデータをデータウェアハウスに格納する処理です。データウェアハウスには様々な種類がありますが、今回はGoogle CloudのBigQueryを利用する想定で、具体的な方法論を紹介します。



- BigQueryへの書込はまあまあ大変
    - スキーマはちゃんとアップデートする必要がある（少なくともGoの場合）
    - 流量もうまくコントロールする必要がある
- 書込の方法
    - Storage Write API
    - Legacy API
    - Data Load Jobs
- Storage Write APIの利用
    - 低コスト
    - 高い流量
    - ただしAPI利用にクセがある（少なくともGoの場合）