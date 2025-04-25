# _TOML.ahk Usage Instructions

## Introduction

_TOML.ahk is a TOML configuration file parser and generator for AutoHotkey v2. It provides a simple API to read and write TOML format configuration files while preserving comments and formatting in the file.

## Basic Usage

### Include the Script

```autohotkey
#Include _TOML.ahk
```

### Read TOML File

Use the `toml_read()` function to read a TOML file:

```autohotkey
; Read configuration file
config := toml_read("config.toml")
```

### Write TOML File

Use the `toml_write()` function to write a TOML file:

```autohotkey
; Write configuration file
toml_write("config.toml", config)
```

## TOML Structure Read/Write Examples

Assume the following TOML file content:

```toml
# This is an example configuration file
title = "TOML Example"
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
name = "Zhang San"
age = 30

[nested]
  [nested.level1]
    [nested.level1.level2]
    deep_key = "Deeply nested value"

[[items]]
name = "Item 1"
value = 100

[[items]]
name = "Item 2"
value = 200
tags = ["tag1", "tag2"]
```

### 1. Reading Data of Different Structures

```autohotkey
#Include _TOML.ahk
; Read configuration file
config := toml_read("test.toml")

; Read basic types
title := config["title"]         ; String: "TOML Example"
MsgBox "Title: " title
version := config["version"]     ; Float: 1.0
MsgBox "Version: " version
enabled := config["enabled"]     ; Boolean: true
MsgBox "Enabled status: " enabled

; Read values from a table/section
serverHost := config["server"]["host"]    ; "localhost"
MsgBox "Server Host: " serverHost
dbEnabled := config["database"]["enabled"] ; true
MsgBox "Database Enabled Status: " dbEnabled

; Check if a key exists
if (config.Has("server") && config["server"].Has("host")) {
    MsgBox "Server Host: " config["server"]["host"]
}
```

### 2. Iterating Through Arrays and Dictionaries (Maps)

```autohotkey
#Include _TOML.ahk
; Read configuration file
config := toml_read("test.toml")

; Iterate through an array
databaseUrls := config["database"]["urls"]
MsgBox "Number of Database URLs: " databaseUrls.Length

; Method 1: Iterate using index
loop databaseUrls.Length {
    MsgBox "URL " A_Index ": " databaseUrls[A_Index]
}

; Method 2: Iterate using for loop
for url in databaseUrls {
    MsgBox "Database URL: " url
}

; Iterate through a table/dictionary (Map)
serverConfig := config["server"]
for key, value in serverConfig {
    MsgBox "Server Config: " key " = " value
}

; Check if 'items' exists and is an array
if (config.Has("items") && IsObject(config["items"]) && config["items"] is Array) {
    ; Iterate through table array
    items := config["items"]
    for index, item in items {
        MsgBox "Item " index " Name: " item["name"] ", Value: " item["value"]

        ; Check and iterate through tags array within the item
        if (item.Has("tags")) {
            tagList := ""
            for tag in item["tags"]
                tagList .= tag ", "
            MsgBox "Item " index " Tags: " RTrim(tagList, ", ")
        }
    }
} else {
    MsgBox "'items' array not found or 'items' is not an array type"
}
```

### 3. Handling Deeply Nested Structures

```autohotkey
#Include _TOML.ahk
; Read configuration file
config := toml_read("test.toml")

; Read deeply nested value
deepValue := config["nested"]["level1"]["level2"]["deep_key"]
MsgBox "Deeply nested value: " deepValue

; Recursively iterate through nested structure
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

; Iterate through the entire configuration
configDump := RecursiveWalk(config)
MsgBox "Configuration Structure:`n" configDump
```

### 4. Modifying and Writing Complex Structures

```autohotkey
#Include _TOML.ahk
; Read configuration file
config := toml_read("test.toml")

; Modify basic value
config["title"] := "Updated Title"

; Modify nested structure
config["server"]["port"] := 9090
config["nested"]["level1"]["level2"]["deep_key"] := "New deep value"

; Modify array element
config["database"]["urls"][1] := "new-localhost:5432"

; Add new array element
config["database"]["urls"].Push("third-db:5432")

; Remove the second element from the array
config["database"]["urls"].RemoveAt(2)

; Modify table array element
if (config["items"].Length >= 2)
    config["items"][2]["value"] := 250

; Add new nested structure
config["newSection"] := Map()
config["newSection"]["subSection"] := Map()
config["newSection"]["subSection"]["key"] := "New Value"

; Add new table array element
newItem := Map("name", "Item 3", "value", 300)
config["items"].Push(newItem)

; Write to file
toml_write("test.toml", config)
```

### 5. Creating Complex TOML Structures

```autohotkey
#Include _TOML.ahk

; Create new configuration
config := Map()

; Add basic values
config["app"] := "MyApp"
config["version"] := 1.0

; Add nested structure
config["server"] := Map()
config["server"]["host"] := "127.0.0.1"
config["server"]["port"] := 8080

; Add deeply nested structure
config["settings"] := Map()
config["settings"]["advanced"] := Map()
config["settings"]["advanced"]["debug"] := Map()
config["settings"]["advanced"]["debug"]["enabled"] := true
config["settings"]["advanced"]["debug"]["level"] := "verbose"

; Add array
config["paths"] := ["data", "logs", "temp"]

; Add table array
config["users"] := []
config["users"].Push(Map("id", 1, "name", "User 1", "roles", ["admin", "user"]))
config["users"].Push(Map("id", 2, "name", "User 2", "roles", ["user"]))

; Write to file
toml_write("new_complex_config.toml", config)
```

## Notes

1.  When reading a TOML file, all data is parsed into corresponding AutoHotkey data types:
    *   String → String
    *   Integer → Integer
    *   Float → Float
    *   Boolean → true/false
    *   Array → Array
    *   Table/Section → Map

2.  When writing a TOML file, the script tries to preserve the original file's comments and formatting as much as possible.

3.  If the original file does not exist, a new file will be created.

4.  A backup file (.bak extension) is automatically created before writing. If writing fails, it will be automatically restored.

5.  For deeply nested structures, ensure each level is a valid Map object; otherwise, it may cause errors.

6.  Table Arrays in TOML are represented as an Array of Maps in AutoHotkey.
