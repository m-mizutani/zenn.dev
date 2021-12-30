---
title: "Regoチートシート"
---


この章ではRegoによるルール表現のパターンをひたすら列挙していきます。

# デバッグ

## 値のチェック

```rego
r := input.user
print(r)
```

## トレース

explainオプションを有効化すると表示される。

```rego
trace(sprintf("x = %d", [x]))
```

# 文字列操作

## 整形

```rego
"blue 5" == sprintf("%s %d", ["blue", 5])
```

## 文字列の結合・分割
```rego
"red, yellow, blue" == concat(", ", ["red", "yellow", "blue"])
["red", "yellow", "blue"] == split("red, yellow, blue", ", ")
```

## 部分一致
```rego
contains("blue", "l")
2 == indexof("blue", "u")
startswith("blue", "bl")
endswith("blue", "ue")
```

## 小文字化・大文字化
```rego
"blue" == lower("BLUE")
"BLUE" == upper("blue")
```

## 抜き出し
```rego
"blue!" == substring("the blue!?", 4, 5)
```

## 切り取り
```rego
"blue" == trim("_blue!", "_!") # 第2引数は文字セット
"blue" == trim_left("e__blue", "e_") # 第2引数は文字セット
"blue" == trim_right("blue__b", "_b") # 第2引数は文字セット
"blue" == trim_prefix("bblue", "b") # 第2引数は文字列
"blue" == trim_suffix("bluee", "e") # 第2引数は文字列
"blue" == trim_space("   blue   ")
```

## 正規表現の一致
```rego
regex.match("[a-z]+", "_blue_")
```

# 配列・集合操作

## 結合（配列）
```rego
["blue", "yellow", "red"] == array.concat(["blue", "yellow"], ["red"])
```

## 抜き出し（配列）
```rego
["yellow", "blue"] == array.slice(["red", "yellow", "blue"], 1, 3)
```

## 要素数（配列・集合）
```rego
3 == count(["red", "yellow", "blue"])
```

## 最大値・最小値・合計（配列・集合）

```rego
5 == max([3, 2, 5, 1, 4])
1 == min([3, 2, 5, 1, 4])
15 == sum([3, 2, 5, 1, 4])
```

## ソート（配列・集合）

返り値は配列になります。

```rego
[1, 2, 3, 4, 5] == sort([3, 2, 5, 1, 4]) # array
[1, 2, 3, 4, 5] == sort({3, 2, 5, 1, 4}) # set
["blue", "red", "yellow"] == sort(["red", "yellow", "blue"])
```

## 積集合・和集合・差集合（集合）

```rego
{"blue"} == {"blue", "red"} & {"orange", "blue"}
{"blue", "red", "orange"} == {"blue", "red"} | {"orange", "blue"}
{"blue"} == {"blue", "red"} - {"red"}
```

# オブジェクト（マップ型）操作

## 値の取得（デフォルト値を指定）

```rego
dict := {
    "white": 3,
    "blue": 5,
}
1 == object.get(dict, "none", 1)
```

## キーの集合の取得

```rego
dict := {
    "white": 3,
    "blue": 5,
}

{"white", "blue"} == {x | dict[x]}
```

## 値の集合の取得

```rego
dict := {
    "white": 3,
    "blue": 5,
}

{3, 5} == {dict[x] | dict[x]}
```

## 特定キーの除外

```rego
dict := {
    "red": 2,
    "white": 3,
    "blue": 5,
}

{"blue": 5} == object.remove(dict, ["white", "red"])
```

## 特定キーを残す

```rego
dict := {
    "red": 2,
    "white": 3,
    "blue": 5,
}

{"blue": 5} == object.filter(dict, ["blue"])
```

## オブジェクトの合成

```rego
obj1 := {
    "white": 3,
    "blue": 0,
}
obj2 := {
    "red": 2,
    "blue": 5,
}

{
    "red": 2,
    "white": 3,
    "blue": 5, # 後勝ちでobj2が優先
} == object.union(obj1, obj2)
```

# マッチ

## 最低1つにマッチ

### 配列

```rego
    arr := ["red", "blue", "yellow"]
    "blue" == arr[_]
```

### オブジェクト型

```rego
    obj := {
        "red": 2,
        "white": 3,
        "blue": 5,
    }
    5 == obj[_]
```

## 全部にマッチ

### 配列

```rego
arr := [1, 1, 1]
3 == count([x | arr[x] == 1])
```

### オブジェクト型

```rego
obj := {
    "red": 1,
    "yellow": 1,
    "blue": 1,
}
3 == count([x | obj[x] == 1])
```

## JOIN

```rego
users = [
    {
        "name": "alice",
        "id": 1,
    },
    {
        "name": "bob",
        "id": 2,
    },
]
assigns = [
    {
        "id": 1,
        "role": "admin",
    },
    {
        "id": 1,
        "role": "reader",
    },
    {
        "id": 2,
        "role": "reader",
    },
]

some x, y
users[x].name == "alice"
assigns[y].id == users[x].id
assigns[y].role == "admin"
```
