---
title: "実践セキュリティ監視基盤構築(16):  ログの変換・書込"
emoji: "🔎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["security", "monitoring"]
published: false
---

- 正規化しなくてもログのスキーマ変換は必要
    - 受け入れ先のデータストアに対応させる
        - ネスト非対応の場合にフラットなフィールドに変換するとか
        - 非対応のフィールド名を変更するとか
    - スキーマがおかしいログとか世の中に死ぬほどある
        - 同じフィールド名なのに全然型が違う
            - arrayとmapが混在
            - array of stringとstringが混在
            - stringとnumberが混在
        - 型は同じなのにフォーマットが違う
            - 時刻とか
- テスト可能性が重要
    - どうしても一定ロジックを書く必要がある
        - 正しく動くかの検証が必要
    - こちらが立てばあちらが立たず
        - 回帰テストしないと死
- BigQueryへの書込はまあまあ大変
    - スキーマはちゃんとアップデートする必要がある（少なくともGoの場合）
    - 流量もうまくコントロールする必要がある
- Storage Write APIの利用
    - 低コスト
    - 高い流量
    - ただしAPI利用にクセがある（少なくともGoの場合）