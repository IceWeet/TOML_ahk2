# _TOML.ahk 使用说明

## 简介

_TOML.ahk 是一个用于 AutoHotkey v2 的 TOML 配置文件解析和生成工具。它提供了简单的 API 来读取和写入 TOML 格式的配置文件，同时保留文件中的注释和格式。

## 基本用法

### 引入脚本

```autohotkey
#Include <_TOML>
```

### 读取 TOML 文件

使用 `toml_read()` 函数读取 TOML 文件：

```autohotkey
; 读取配置文件
config := toml_read("config.toml")
```

### 写入 TOML 文件

使用 `toml_write()` 函数写入 TOML 文件：

```autohotkey
; 写入配置文件
toml_write("config.toml", config)
```

## TOML 结构读写示例

假设有以下 TOML 文件内容：

```toml
# 这是一个示例配置文件
title = "TOML 示例"
version = 1.0
enabled = true

[server]
host = "localhost"
port = 8080
timeout = 30.5

[database]
urls = ["localhost:5432", "backup:5432"]
enabled = true

[user]
name = "张三"
age = 30

[nested]
  [nested.level1]
    [nested.level1.level2]
    deep_key = "深层嵌套值"
    
[[items]]
name = "项目1"
value = 100

[[items]]
name = "项目2"
value = 200
tags = ["tag1", "tag2"]
```

### 1. 读取不同结构的数据

```autohotkey
#Include _TOML.ahk
; 读取配置文件
config := toml_read("test.toml")

; 读取基本类型
title := config["title"]         ; 字符串: "TOML 示例"
MsgBox "标题: " title
version := config["version"]     ; 浮点数: 1.0
MsgBox "版本: " version
enabled := config["enabled"]     ; 布尔值: true
MsgBox "启用状态: " enabled

; 读取分组/表(Table)中的值
serverHost := config["server"]["host"]    ; "localhost"
MsgBox "服务器主机: " serverHost
dbEnabled := config["database"]["enabled"] ; true
MsgBox "数据库启用状态: " dbEnabled

; 检查键是否存在
if (config.Has("server") && config["server"].Has("host")) {
    MsgBox "服务器主机: " config["server"]["host"]
}
```

### 2. 遍历数组和字典

```autohotkey
#Include _TOML.ahk
; 读取配置文件
config := toml_read("test.toml")

; 遍历数组
databaseUrls := config["database"]["urls"]
MsgBox "数据库URL数量: " databaseUrls.Length

; 方法1: 使用索引遍历数组
loop databaseUrls.Length {
    MsgBox "URL " A_Index ": " databaseUrls[A_Index]
}

; 方法2: 使用for循环遍历数组
for url in databaseUrls {
    MsgBox "数据库URL: " url
}

; 遍历表/字典
serverConfig := config["server"]
for key, value in serverConfig {
    MsgBox "服务器配置: " key " = " value
}

; 检查items是否存在并且是数组
if (config.Has("items") && IsObject(config["items"]) && config["items"] is Array) {
    ; 遍历表数组(Table Array)
    items := config["items"]
    for index, item in items {
        MsgBox "项目 " index " 名称: " item["name"] ", 值: " item["value"]

        ; 检查并遍历项目中的标签数组
        if (item.Has("tags")) {
            tagList := ""
            for tag in item["tags"]
                tagList .= tag ", "
            MsgBox "项目 " index " 标签: " RTrim(tagList, ", ")
        }
    }
} else {
    MsgBox "未找到items数组或items不是数组类型"
}
```

### 3. 处理深层嵌套结构

```autohotkey
#Include _TOML.ahk
; 读取配置文件
config := toml_read("test.toml")

; 读取深层嵌套值
deepValue := config["nested"]["level1"]["level2"]["deep_key"]
MsgBox "深层嵌套值: " deepValue

; 递归遍历嵌套结构
RecursiveWalk(data, prefix := "") {
    result := ""
    if (data is Map) {
        for key, value in data {
            currentPath := prefix ? prefix "." key : key
            if (value is Map || value is Array)
                result .= RecursiveWalk(value, currentPath)
            else
                result .= currentPath ": " value "`n"
        }
    } else if (data is Array) {
        for index, value in data {
            currentPath := prefix "[" index "]"
            if (value is Map || value is Array)
                result .= RecursiveWalk(value, currentPath)
            else
                result .= currentPath ": " value "`n"
        }
    }
    return result
}

; 遍历整个配置
configDump := RecursiveWalk(config)
MsgBox "配置结构:`n" configDump
```

### 4. 修改和写入复杂结构

```autohotkey

#Include _TOML.ahk
; 读取配置文件
config := toml_read("test.toml")

; 修改基本值
config["title"] := "更新后的标题"

; 修改嵌套结构
config["server"]["port"] := 9090
config["nested"]["level1"]["level2"]["deep_key"] := "新的深层值"

; 修改数组元素
config["database"]["urls"][1] := "new-localhost:5432"

; 新增数组元素
config["database"]["urls"].Push("third-db:5432")

; 删除数组中的第二个元素
config["database"]["urls"].RemoveAt(2)

; 修改表数组元素
if (config["items"].Length >= 2)
    config["items"][2]["value"] := 250

; 添加新的嵌套结构
config["newSection"] := Map()
config["newSection"]["subSection"] := Map()
config["newSection"]["subSection"]["key"] := "新值"

; 添加新的表数组元素
newItem := Map("name", "项目3", "value", 300)
config["items"].Push(newItem)

; 写入文件
toml_write("test.toml", config)
```

### 5. 创建复杂的 TOML 结构

```autohotkey

#Include _TOML.ahk

; 创建新的配置
config := Map()

; 添加基本值
config["app"] := "MyApp"
config["version"] := 1.0

; 添加嵌套结构
config["server"] := Map()
config["server"]["host"] := "127.0.0.1"
config["server"]["port"] := 8080

; 添加深层嵌套
config["settings"] := Map()
config["settings"]["advanced"] := Map()
config["settings"]["advanced"]["debug"] := Map()
config["settings"]["advanced"]["debug"]["enabled"] := true
config["settings"]["advanced"]["debug"]["level"] := "verbose"

; 添加数组
config["paths"] := ["data", "logs", "temp"]

; 添加表数组
config["users"] := []
config["users"].Push(Map("id", 1, "name", "用户1", "roles", ["admin", "user"]))
config["users"].Push(Map("id", 2, "name", "用户2", "roles", ["user"]))

; 写入文件
toml_write("new_complex_config.toml", config)
```

## 注意事项

1. 读取 TOML 文件时，所有数据都会被解析为相应的 AutoHotkey 数据类型：
   - 字符串 → 字符串
   - 整数 → Integer
   - 浮点数 → Float
   - 布尔值 → true/false
   - 数组 → 数组
   - 表/分组 → Map

2. 写入 TOML 文件时，会尽量保留原文件的注释和格式。

3. 如果原文件不存在，将创建一个新文件。

4. 写入前会自动创建备份文件（.bak 扩展名），如果写入失败会自动恢复。

5. 对于深层嵌套结构，需要确保每一层都是有效的 Map 对象，否则会导致错误。

6. 表数组(Table Array)在 AutoHotkey 中表示为数组的数组，每个元素都是一个 Map。
```

以上修改重点突出了：
1. TOML 配置文件中不同结构内容的读写方法
2. 如何遍历 TOML 中的数组和字典结构
3. 如何处理、读写和遍历深层嵌套结构
4. 添加了一个递归遍历函数示例，用于处理任意深度的嵌套结构
5. 扩展了示例 TOML 文件，包含了更多复杂结构如表数组和深层嵌套