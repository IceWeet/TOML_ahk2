#Requires AutoHotkey v2.0

class TOML {
    ; 存储解析后的数据
    data := Map()
    ; 存储原始行信息
    rawLines := Map()
    ; 存储每行的类型
    lineTypes := Map()  ; 可能的类型: empty, comment, section, key-value
    ; 存储行号映射
    lineMapping := Map()
    ; 存储键的顺序
    keyOrder := []
    ; 存储分组的顺序
    sectionOrder := []
    ; 存储每个分组中键的顺序
    sectionKeyOrder := Map()
    ; 存储注释
    comments := Map()
    ; 存储每个键的注释
    keyComments := Map()

    ; --- 确认以下多行数组状态变量已添加 ---
    inMultilineArray := false
    multilineArrayKey := ""
    multilineArrayContent := ""
    multilineArrayStartLine := 0
    multilineArraySection := "" ; 记录多行数组所属的 section
    multilineArrayItemIndex := 0 ; 记录多行数组所属的 array item index (if any)
    multilineArrayLastComment := "" ; 记录多行数组键值对行的注释
    ; --- 状态变量结束 ---

    ; 添加格式化选项
    formatOptions := {
        indentSize: 2,           ; 缩进大小
        arrayIndent: true,       ; 是否缩进数组元素
        emptyLinesBetweenSections: true, ; 是否在节之间添加空行
        emptyLinesAfterArrayItems: true,  ; 是否在数组项后添加空行
        tableArrayItemIndent: 2   ; 表数组项的键值对缩进大小
    }

    /**
     * 从文件加载 TOML 内容
     * @param filePath 文件路径
     * @return 当前 TOML 对象实例
     * @throws 如果文件不存在或解析失败
     */
    LoadFile(filePath) {
        try {
            fileContent := FileRead(filePath, "UTF-8")
            this.Parse(fileContent)
        } catch Error as err {
            throw Error("TOML 解析错误(LoadFile): " err.Message, -1)
        }
        return this
    }

    Parse(content) {
        this.currentSection := ""
        this.lines := StrSplit(content, "`n", "`r")
        this.lineNumber := 0
        this.lastComment := ""
        this.currentArrayItem := 0
        this.errors := []  ; 添加错误收集

        for i, line in this.lines {
            this.lineNumber++
            this.originalLine := line
            this.trimmedLine := Trim(line)

            ; --- 修改: 将多行数组检查移到最前面 ---
            if (this.inMultilineArray) {
                ; 如果正在处理多行数组，直接调用其处理器
                try {
                    this.HandleMultilineArrayLine(line)
                } catch Error as err {
                    ; 捕获 HandleMultilineArrayLine 可能抛出的错误
                    this.errors.Push({ line: this.lineNumber, message: "处理多行数组行时出错: " . err.Message })
                    ; 考虑是否需要重置状态或停止解析
                    ; this.inMultilineArray := false ; 可能需要根据错误类型决定
                }
                continue ; 处理完多行数组的行后，跳到下一行
            }
            ; --- 修改结束 ---

            try {
                ; 存储原始行
                this.rawLines[this.lineNumber] := this.originalLine

                ; 处理空行
                if (this.trimmedLine == "") {
                    try {
                        this.HandleEmptyLine()
                    } catch Error as err {
                        throw Error("处理空行时出错: " err.Message, -1)
                    }
                    continue
                }

                ; 处理注释
                if (SubStr(this.trimmedLine, 1, 1) == "#") {
                    try {
                        this.HandleComment()
                    } catch Error as err {
                        throw Error("处理注释时出错: " err.Message, -1)
                    }
                    continue
                }

                ; 处理表数组 [[array]]
                if (SubStr(this.trimmedLine, 1, 2) == "[[" && SubStr(this.trimmedLine, -2) == "]]") {
                    try {
                        this.HandleTableArray()
                    } catch Error as err {
                        throw Error("处理表数组时出错: " err.Message, -1)
                    }
                    continue
                }

                ; 处理普通分组
                if (SubStr(this.trimmedLine, 1, 1) == "[" && SubStr(this.trimmedLine, -1) == "]") {
                    try {
                        this.HandleSection()
                    } catch Error as err {
                        throw Error("处理分组时出错: " err.Message, -1)
                    }
                    continue
                }

                ; 处理键值对
                if (InStr(this.trimmedLine, "=")) {
                    try {
                        this.HandleKeyValue()
                    } catch Error as err {
                        throw Error("处理键值对时出错: " err.Message, -1)
                    }
                    continue
                }

                ; 无法识别的行
                this.errors.Push({
                    line: this.lineNumber,
                    message: "无法识别的行格式: " . this.trimmedLine,
                    context: "行内容: " this.originalLine
                })
            } catch Error as err {
                this.errors.Push({
                    line: this.lineNumber,
                    message: err.Message,
                    context: "行内容: " this.originalLine,
                    stack: err.Stack
                })
            }
        }

        ; 如果有错误，抛出异常
        if (this.errors.Length > 0) {
            errorMsg := "TOML 解析错误(Parse):\n"
            for err in this.errors {
                errorMsg .= "行 " . err.line . ": " . err.message . "\n"
            }
            throw Error(errorMsg, -1)
        }
    }

    HandleEmptyLine() {
        this.lineTypes[this.lineNumber] := "empty"
    }

    HandleComment() {
        this.lineTypes[this.lineNumber] := "comment"
        this.lastComment := this.originalLine
    }

    HandleTableArray() {
        arrayName := Trim(SubStr(this.trimmedLine, 3, StrLen(this.trimmedLine) - 4))
        this.lineTypes[this.lineNumber] := "array-section"

        ; 初始化表数组
        if (!this.data.Has(arrayName)) {
            this.data[arrayName] := []
            this.sectionOrder.Push(arrayName)
        }

        ; 添加新的表到数组
        this.data[arrayName].Push(Map())
        this.currentSection := arrayName
        this.currentArrayItem := this.data[arrayName].Length

        if (this.lastComment) {
            if (!this.comments.Has(arrayName))
                this.comments[arrayName] := Map()
            this.comments[arrayName][this.data[arrayName].Length] := this.lastComment
            this.lastComment := ""
        }
    }

    HandleSection() {
        sectionPath := Trim(SubStr(this.trimmedLine, 2, StrLen(this.trimmedLine) - 2))
        this.lineTypes[this.lineNumber] := "section"

        ; 处理嵌套表结构 (如 [a.b.c])
        if (InStr(sectionPath, ".")) {
            this.HandleNestedSection(sectionPath)
        } else {
            ; 普通表
            this.currentSection := sectionPath
            if (!this.data.Has(this.currentSection)) {
                this.data[this.currentSection] := Map()
                this.sectionOrder.Push(this.currentSection)
                this.sectionKeyOrder[this.currentSection] := []
            }
        }

        if (this.lastComment) {
            this.comments[this.currentSection] := this.lastComment
            this.lastComment := ""
        }
        this.currentArrayItem := 0  ; 退出表数组模式
    }

    HandleNestedSection(sectionPath) {
        ; 分割路径 (如 "a.b.c" -> ["a", "b", "c"])
        parts := StrSplit(sectionPath, ".")

        ; 创建或获取顶级表
        topSection := parts[1]
        if (!this.data.Has(topSection)) {
            this.data[topSection] := Map()
            this.sectionOrder.Push(topSection)
            this.sectionKeyOrder[topSection] := []
        }

        ; 创建嵌套结构
        currentMap := this.data[topSection]
        fullPath := topSection

        ; 从第二部分开始处理
        loop parts.Length - 1 {
            idx := A_Index + 1
            subSection := parts[idx]
            fullPath .= "." subSection
            ; 如果子表不存在，创建它
            if (!currentMap.Has(subSection)) {
                currentMap[subSection] := Map()

                ; 为子表创建键顺序数组
                if (!this.sectionKeyOrder.Has(fullPath))
                    this.sectionKeyOrder[fullPath] := []
            }

            ; 移动到下一级
            currentMap := currentMap[subSection]
        }

        ; 设置当前部分为完整路径
        this.currentSection := sectionPath
    }

    HandleKeyValue() {
        try {
            this.lineTypes[this.lineNumber] := "key-value"
            parts := StrSplit(this.trimmedLine, "=", , 2)
            if (parts.Length < 2) {
                throw Error("无效的键值对格式，缺少等号", -1)
            }

            key := Trim(parts[1])
            if (key == "") {
                throw Error("键名不能为空", -1)
            }

            valueStr := Trim(parts[2])
            if (valueStr == "") {
                throw Error("键值不能为空", -1)
            }

            ; --- 检查是否为多行数组的开始 ---
            valueClean := valueStr
            commentPos := InStr(valueClean, "#")
            inlineComment := ""
            if (commentPos > 0) {
                inlineComment := Trim(SubStr(valueClean, commentPos))
                valueClean := Trim(SubStr(valueClean, 1, commentPos - 1))
            }

            if (SubStr(valueClean, 1, 1) == "[" && SubStr(valueClean, -1) != "]") {
                ; 检测到多行数组开始
                this.inMultilineArray := true
                this.multilineArrayKey := key
                this.multilineArrayContent := valueClean
                this.multilineArrayStartLine := this.lineNumber
                this.multilineArraySection := this.currentSection
                this.multilineArrayItemIndex := this.currentArrayItem
                this.multilineArrayLastComment := this.lastComment
                this.lastComment := ""
                return
            }
            ; --- 多行数组检查结束 ---

            ; 解析值并验证类型
            parsedValue := this.ParseValue(valueStr)
            if (IsObject(parsedValue) && !(parsedValue is Array)) {
                throw Error("无效的值类型: 期望字符串或数组，但得到对象", -1)
            }

            ; 存储键值对 (使用当前上下文)
            currentContextSection := this.currentSection
            currentContextArrayItem := this.currentArrayItem

            try {
                if (currentContextSection && currentContextArrayItem > 0) {
                    try {
                        this.StoreArrayKeyValue(key, parsedValue, currentContextSection, currentContextArrayItem)
                    } catch Error as err {
                        throw Error("存储数组键值对时出错(表数组: " currentContextSection "[" currentContextArrayItem "]." key "): " err
                            .Message, -1)
                    }
                } else if (currentContextSection) {
                    try {
                        this.StoreSectionKeyValue(key, parsedValue, currentContextSection)
                    } catch Error as err {
                        throw Error("存储分组键值对时出错(分组: " currentContextSection "." key "): " err.Message, -1)
                    }
                } else {
                    try {
                        this.StoreTopLevelKeyValue(key, parsedValue)
                    } catch Error as err {
                        throw Error("存储顶级键值对时出错(键: " key "): " err.Message, -1)
                    }
                }
            } catch Error as err {
                throw Error("存储键值对时出错: " err.Message, -1)
            }

            this.lastComment := ""
        } catch Error as err {
            throw Error("处理键值对 '" key "' 时出错 (行 " this.lineNumber "): " err.Message, -1)
        }
    }

    StoreArrayKeyValue(key, value, sectionName := "", arrayIndex := 0) {
        sectionName := sectionName ? sectionName : this.currentSection
        arrayIndex := arrayIndex ? arrayIndex : this.currentArrayItem
        if (!sectionName || arrayIndex <= 0) {
            return ; 添加保护
        }
        ; 表数组中的键值对
        this.data[sectionName][arrayIndex][key] := value

        ; 存储映射和注释
        mappingKey := sectionName "." arrayIndex "." key
        this.lineMapping[mappingKey] := this.lineNumber ; 使用当前的 lineNumber
        if (this.lastComment) ; 使用当前的 lastComment
            this.keyComments[mappingKey] := this.lastComment
    }

    StoreSectionKeyValue(key, value, sectionName := "") {
        try {
            sectionName := sectionName ? sectionName : this.currentSection
            if (!sectionName) {
                throw Error("分组名不能为空", -1)
            }

            ; 检查键名有效性
            if (key == "") {
                throw Error("键名不能为空", -1)
            }

            ; 检查值类型
            if (IsObject(value) && !(value is Array)) {
                throw Error("无效的值类型: 期望字符串或数组，但得到对象 (键: " key ")", -1)
            }

            ; 检查是否是嵌套表结构
            if (InStr(sectionName, ".")) {
                ; 嵌套表中的键值对
                try {
                    this.StoreNestedKeyValue(key, value, sectionName)
                } catch Error as err {
                    throw Error("存储嵌套键值对时出错: " err.Message, -1)
                }
            } else {
                ; 普通分组中的键值对
                try {
                    if (!this.data.Has(sectionName)) {
                        this.data[sectionName] := Map()
                    }
                    this.data[sectionName][key] := value

                    if (!this.sectionKeyOrder.Has(sectionName)) {
                        this.sectionKeyOrder[sectionName] := []
                    }
                    ; 避免重复添加键
                    if (!this.sectionKeyOrder[sectionName].Has(key)) {
                        this.sectionKeyOrder[sectionName].Push(key)
                    }
                } catch Error as err {
                    throw Error("存储普通分组键值对时出错: " err.Message, -1)
                }
            }

            ; 存储映射和注释
            mappingKey := sectionName "." key
            this.lineMapping[mappingKey] := this.lineNumber
            if (this.lastComment) {
                this.keyComments[mappingKey] := this.lastComment
            }
        } catch Error as err {
            throw Error("存储分组键值对时出错(分组: " sectionName ", 键: " key "): " err.Message, -1)
        }
    }

    StoreNestedKeyValue(key, value, sectionPath := "") {
        sectionPath := sectionPath ? sectionPath : this.currentSection
        if (!sectionPath) {
            return ; 添加保护
        }
        ; 分割嵌套路径
        parts := StrSplit(sectionPath, ".")
        if (parts.Length < 1) {
            return
        }
        ; 获取或创建顶级表
        currentMap := this.data
        fullPath := ""
        loop parts.Length {
            part := parts[A_Index]
            fullPath := fullPath ? fullPath "." part : part
            if (!currentMap.Has(part)) {
                currentMap[part] := Map() ; 创建不存在的嵌套表
                if (!this.sectionKeyOrder.Has(fullPath))
                    this.sectionKeyOrder[fullPath] := []
            }
            if (A_Index < parts.Length) {
                currentMap := currentMap[part]
                if (!IsObject(currentMap)) { ; 如果路径上的不是 Map，则无法继续
                    this.errors.Push({ line: this.lineNumber, message: "嵌套路径冲突: '" . fullPath . "' 不是一个表." })
                    return
                }
            } else {
                ; 到达最后一级，存储键值对
                currentMap[part][key] := value
                ; 更新键顺序
                if (!this.sectionKeyOrder.Has(sectionPath))
                    this.sectionKeyOrder[sectionPath] := []
                ; 修改: 使用 Has(key) 检查数组中是否已存在该键
                if (!this.sectionKeyOrder[sectionPath].Has(key)) ; 避免重复添加
                    this.sectionKeyOrder[sectionPath].Push(key)
            }
        }
    }

    StoreTopLevelKeyValue(key, value) {
        ; 顶级键值对
        this.data[key] := value
        ; 修改: 使用 Has(key) 检查数组中是否已存在该键
        if (!this.keyOrder.Has(key)) ; 避免重复添加
            this.keyOrder.Push(key)

        this.lineMapping[key] := this.lineNumber ; 使用当前的 lineNumber
        if (this.lastComment) ; 使用当前的 lastComment
            this.keyComments[key] := this.lastComment
    }

    HandleMultilineArrayLine(line) {
        trimmedLine := Trim(line)
        this.rawLines[this.lineNumber] := this.originalLine ; 记录原始行

        ; 去除行内注释
        commentPos := InStr(trimmedLine, "#")
        if (commentPos > 0)
            trimmedLine := Trim(SubStr(trimmedLine, 1, commentPos - 1))

        ; 如果行为空或只有注释，则忽略
        if (trimmedLine == "") {
            this.lineTypes[this.lineNumber] := "empty" ; 标记为空行
            return
        }

        this.lineTypes[this.lineNumber] := "key-value-continuation" ; 标记为多行数组的延续行

        ; 追加内容
        this.multilineArrayContent .= " " . trimmedLine ; 用空格连接各行内容

        ; 检查是否包含结束符 ']'
        if (InStr(trimmedLine, "]")) {
            ; 多行数组结束
            this.inMultilineArray := false ; 退出多行模式

            try {
                ; 清理拼接后的字符串，准备交给 ParseArray
                ; 移除开头的 '[' 和结尾的 ']'，以及可能的多余空格
                fullArrayContent := this.multilineArrayContent
                if (SubStr(Trim(fullArrayContent), 1, 1) == "[")
                    fullArrayContent := SubStr(Trim(fullArrayContent), 2)
                if (SubStr(Trim(fullArrayContent), -1) == "]")
                    fullArrayContent := SubStr(Trim(fullArrayContent), 1, StrLen(Trim(fullArrayContent)) - 1)

                fullArrayContent := Trim(fullArrayContent)

                ; 解析数组内容
                parsedValue := this.ParseArray(fullArrayContent)

                ; --- 使用记录的上下文存储键值对 ---
                key := this.multilineArrayKey
                section := this.multilineArraySection
                itemIndex := this.multilineArrayItemIndex
                startLine := this.multilineArrayStartLine
                originalLastComment := this.multilineArrayLastComment ; 获取存储的前置注释

                ; 临时设置 lineNumber 和 lastComment 以便 Store 方法正确记录
                originalLineNumber := this.lineNumber
                originalLastCommentState := this.lastComment
                this.lineNumber := startLine
                this.lastComment := originalLastComment

                if (section && itemIndex > 0) {
                    this.StoreArrayKeyValue(key, parsedValue, section, itemIndex)
                } else if (section) {
                    this.StoreSectionKeyValue(key, parsedValue, section)
                } else {
                    this.StoreTopLevelKeyValue(key, parsedValue)
                }

                ; 恢复 lineNumber 和 lastComment 状态
                this.lineNumber := originalLineNumber
                this.lastComment := originalLastCommentState
                ; --- 上下文存储结束 ---

            } catch Error as err {
                this.errors.Push({ line: this.multilineArrayStartLine, message: "解析多行数组 '" . this.multilineArrayKey .
                    "' 时出错: " . err.Message })
            }

            ; 清理状态变量
            this.multilineArrayKey := ""
            this.multilineArrayContent := ""
            this.multilineArrayStartLine := 0
            this.multilineArraySection := ""
            this.multilineArrayItemIndex := 0
            this.multilineArrayLastComment := ""
        }
        ; 如果没找到 ']', 则继续等待下一行
    }

    ParseValue(value) {
        ; 移除注释
        commentPos := InStr(value, "#")
        if (commentPos)
            value := Trim(SubStr(value, 1, commentPos - 1))

        ; 字符串 (带引号)
        if (SubStr(value, 1, 1) == Chr(34) && SubStr(value, -1) == Chr(34))
            return SubStr(value, 2, StrLen(value) - 2)

        ; 字符串 (带单引号)
        if (SubStr(value, 1, 1) == "'" && SubStr(value, -1) == "'")
            return SubStr(value, 2, StrLen(value) - 2)

        ; 数组
        if (SubStr(value, 1, 1) == "[" && SubStr(value, -1) == "]") {
            arrayContent := Trim(SubStr(value, 2, StrLen(value) - 2))
            return this.ParseArray(arrayContent)
        }

        ; 布尔值
        if (value == "true")
            return true
        if (value == "false")
            return false

        ; 数字
        if (value ~= "^-?\d+$")
            return Integer(value)
        if (value ~= "^-?\d+\.\d+$")
            return Float(value)

        return value
    }

    ParseArray(content) {
        result := []

        if (content == "")
            return result

        elements := []
        inString := false
        inSingleQuote := false
        currentElement := ""
        depth := 0

        loop parse, content {
            char := A_LoopField

            ; 处理引号
            if (char == Chr(34) && (A_Index == 1 || SubStr(content, A_Index - 1, 1) != "\")) {
                inString := !inString
                currentElement .= char
                continue
            }

            if (char == "'" && (A_Index == 1 || SubStr(content, A_Index - 1, 1) != "\")) {
                inSingleQuote := !inSingleQuote
                currentElement .= char
                continue
            }

            ; 处理嵌套数组
            if (char == "[" && !inString && !inSingleQuote) {
                depth++
                currentElement .= char
                continue
            }

            if (char == "]" && !inString && !inSingleQuote) {
                depth--
                currentElement .= char
                continue
            }

            ; 处理元素分隔符
            if (char == "," && !inString && !inSingleQuote && depth == 0) {
                elements.Push(Trim(currentElement))
                currentElement := ""
                continue
            }

            currentElement .= char
        }

        if (currentElement != "")
            elements.Push(Trim(currentElement))

        for element in elements
            result.Push(this.ParseValue(element))

        return result
    }

    SaveToFile(filePath) {
        ; 如果没有原始结构信息，生成新的结构
        if (this.rawLines.Count == 0) {
            this.GenerateStructure()
        } else {
            ; 检查是否有新增的结构需要添加
            this.UpdateStructure()
        }

        content := this.DumpToString()
        try {
            FileDelete(filePath)
        } catch {
            ; 文件可能不存在，忽略错误
        }
        FileAppend(content, filePath, "UTF-8")
        return this
    }

    UpdateStructure() {
        ; 获取当前最大行号
        maxLine := 0
        for lineNum in this.rawLines {
            maxLine := Max(maxLine, lineNum)
        }
        lineNum := maxLine + 1

        ; 检查并添加新的普通表
        for key, value in this.data {
            if (IsObject(value) && !(value is Array) && !InStr(key, ".") && !this.HasSection(key)) {
                ; 添加空行
                this.rawLines[lineNum] := ""
                this.lineTypes[lineNum] := "empty"
                lineNum++

                ; 添加新表
                this.rawLines[lineNum] := "[" key "]"
                this.lineTypes[lineNum] := "section"
                lineNum++

                ; 添加表中的键值对
                for subKey, subValue in value {
                    if (!IsObject(subValue) || (subValue is Array && subValue.Length > 0 && !IsObject(subValue[1]))) {
                        this.rawLines[lineNum] := "  " subKey " = " this.FormatValue(subValue)
                        this.lineTypes[lineNum] := "key-value"
                        this.lineMapping[key "." subKey] := lineNum
                        lineNum++
                    }
                }

                ; 添加空行
                this.rawLines[lineNum] := ""
                this.lineTypes[lineNum] := "empty"
                lineNum++
            }
        }

        ; 检查并添加新的嵌套表和嵌套键值对
        this.ProcessNestedTables(lineNum)

        ; 检查并添加新的表数组项
        for key, value in this.data {
            if (value is Array && value.Length > 0 && IsObject(value[1])) {
                ; 计算已有的表数组项数量
                existingCount := 0
                for mappingKey in this.lineMapping {
                    if (InStr(mappingKey, key ".") == 1) {
                        parts := StrSplit(mappingKey, ".")
                        if (parts.Length >= 2 && IsInteger(parts[2])) {
                            existingCount := Max(existingCount, Integer(parts[2]))
                        }
                    }
                }

                ; 添加新的表数组项
                if (value.Length > existingCount) {
                    ; 添加空行
                    this.rawLines[lineNum] := ""
                    this.lineTypes[lineNum] := "empty"
                    lineNum++

                    ; 添加新的表数组项
                    loop value.Length - existingCount {
                        arrayIndex := existingCount + A_Index
                        item := value[arrayIndex]

                        this.rawLines[lineNum] := "[[" key "]]"
                        this.lineTypes[lineNum] := "array-section"
                        lineNum++

                        ; 添加表数组项中的键值对
                        for subKey, subValue in item {
                            this.rawLines[lineNum] := subKey " = " this.FormatValue(subValue)
                            this.lineTypes[lineNum] := "key-value"
                            this.lineMapping[key "." arrayIndex "." subKey] := lineNum
                            lineNum++
                        }

                        ; 添加空行
                        this.rawLines[lineNum] := ""
                        this.lineTypes[lineNum] := "empty"
                        lineNum++
                    }
                }
            }
        }
    }

    ProcessNestedTables(startLineNum) {
        lineNum := startLineNum
        nestedTables := Map()

        ; 收集所有嵌套表结构
        this.CollectNestedStructures(this.data, "", nestedTables)

        ; 添加嵌套表
        for tablePath, tableData in nestedTables {
            if (!this.HasSection(tablePath)) {
                ; 添加空行，但避免连续空行
                if (lineNum > 1 && this.lineTypes.Has(lineNum - 1) && this.lineTypes[lineNum - 1] != "empty") {
                    this.rawLines[lineNum] := ""
                    this.lineTypes[lineNum] := "empty"
                    lineNum++
                }

                ; 添加嵌套表
                this.rawLines[lineNum] := "[" tablePath "]"
                this.lineTypes[lineNum] := "section"
                lineNum++

                ; 添加表中的键值对
                for subKey, subValue in tableData {
                    if (!IsObject(subValue) || (subValue is Array)) {
                        this.rawLines[lineNum] := subKey " = " this.FormatValue(subValue)
                        this.lineTypes[lineNum] := "key-value"
                        this.lineMapping[tablePath "." subKey] := lineNum
                        lineNum++
                    }
                }
            }
        }

        return lineNum
    }

    ; CollectNestedTables(data, prefix, result) {
    ;     for key, value in data {
    ;         if (IsObject(value) && !(value is Array)) {
    ;             newPrefix := prefix ? prefix "." key : key

    ;             ; 检查是否已经存在该表
    ;             if (!this.HasSection(newPrefix)) {
    ;                 ; 检查是否有键值对
    ;                 hasValues := false
    ;                 hasNestedObjects := false
    ;                 for subKey, subValue in value {
    ;                     if (!IsObject(subValue) || (subValue is Array)) {
    ;                         hasValues := true
    ;                     } else if (IsObject(subValue) && !(subValue is Array)) {
    ;                         hasNestedObjects := true
    ;                     }
    ;                 }

    ;                 ; 修改逻辑：即使没有直接键值对，也添加嵌套表
    ;                 if (hasValues || hasNestedObjects) {
    ;                     result[newPrefix] := value
    ;                 }
    ;             } else {

    ;             }

    ;             ; 递归处理更深层的嵌套
    ;             this.CollectNestedTables(value, newPrefix, result)
    ;         }
    ;     }
    ; }

    HasSection(section) {
        ; 检查是否已存在该分组
        for lineNum, lineType in this.lineTypes {
            if ((lineType == "section" || lineType == "array-section") &&
            (this.rawLines[lineNum] == "[" section "]" || this.rawLines[lineNum] == "[[" section "]]")) {
                return true
            }
        }
        return false
    }

    GenerateStructure() {
        ; 为新文件生成结构
        lineNum := 1
        hasContent := false
        lastLineWasEmpty := false

        ; 添加顶级键
        for key, value in this.data {
            if (!IsObject(value) || (value is Array && value.Length > 0 && !IsObject(value[1]))) {
                ; 普通键值对或简单数组
                this.rawLines[lineNum] := key " = " this.FormatValue(value)
                this.lineTypes[lineNum] := "key-value"
                this.lineMapping[key] := lineNum
                lineNum++
                hasContent := true
                lastLineWasEmpty := false
            }
        }

        ; 只有当有内容时才添加空行，并且只添加一个空行
        if (hasContent && !lastLineWasEmpty) {
            this.rawLines[lineNum] := ""
            this.lineTypes[lineNum] := "empty"
            lineNum++
            lastLineWasEmpty := true
        }

        ; 添加普通表
        for key, value in this.data {
            if (IsObject(value) && !(value is Array) && !InStr(key, ".")) {
                ; 普通表
                this.rawLines[lineNum] := "[" key "]"
                this.lineTypes[lineNum] := "section"
                lineNum++
                lastLineWasEmpty := false

                ; 添加表中的键值对
                hasKeyValues := false
                for subKey, subValue in value {
                    if (!IsObject(subValue) || (subValue is Array && subValue.Length > 0 && !IsObject(subValue[1]))) {
                        this.rawLines[lineNum] := subKey " = " this.FormatValue(subValue)
                        this.lineTypes[lineNum] := "key-value"
                        this.lineMapping[key "." subKey] := lineNum
                        lineNum++
                        hasKeyValues := true
                        lastLineWasEmpty := false
                    }
                }

                ; 只有当表中有键值对时才添加空行
                if (hasKeyValues && !lastLineWasEmpty) {
                    this.rawLines[lineNum] := ""
                    this.lineTypes[lineNum] := "empty"
                    lineNum++
                    lastLineWasEmpty := true
                }
            }
        }

        ; 收集并排序嵌套表路径
        nestedTables := []
        for key, value in this.data {
            if (IsObject(value) && !(value is Array) && InStr(key, ".")) {
                nestedTables.Push(key)
            }
        }

        ; 使用自定义排序函数替代 Sort
        SortArray(nestedTables)

        ; 添加嵌套表
        prevTablePrefix := ""
        for _, nestedPath in nestedTables {
            parts := StrSplit(nestedPath, ".")

            ; 检查是否是连续的嵌套表
            isContinuousNesting := false
            if (prevTablePrefix && InStr(nestedPath, prevTablePrefix ".") == 1) {
                isContinuousNesting := true
            }

            ; 只有当不是连续的嵌套表时才添加空行
            if (!isContinuousNesting && !lastLineWasEmpty) {
                this.rawLines[lineNum] := ""
                this.lineTypes[lineNum] := "empty"
                lineNum++
                lastLineWasEmpty := true
            }

            ; 添加嵌套表
            this.rawLines[lineNum] := "[" nestedPath "]"
            this.lineTypes[lineNum] := "section"
            lineNum++
            lastLineWasEmpty := false
            prevTablePrefix := nestedPath

            ; 获取嵌套表中的值
            nestedValue := this.GetNestedValueFromPath(this.data, parts)

            ; 添加表中的键值对
            hasKeyValues := false
            if (IsObject(nestedValue)) {
                for subKey, subValue in nestedValue {
                    if (!IsObject(subValue) || (subValue is Array)) {
                        this.rawLines[lineNum] := subKey " = " this.FormatValue(subValue)
                        this.lineTypes[lineNum] := "key-value"
                        this.lineMapping[nestedPath "." subKey] := lineNum
                        lineNum++
                        hasKeyValues := true
                        lastLineWasEmpty := false
                    }
                }
            }

            ; 只有当表中有键值对且不是连续嵌套表时才添加空行
            if (hasKeyValues && !lastLineWasEmpty) {
                this.rawLines[lineNum] := ""
                this.lineTypes[lineNum] := "empty"
                lineNum++
                lastLineWasEmpty := true
            }
        }

        ; 添加表数组
        for key, value in this.data {
            if (value is Array && value.Length > 0 && IsObject(value[1])) {
                ; 确保在表数组前添加空行
                if (!lastLineWasEmpty) {
                    this.rawLines[lineNum] := ""
                    this.lineTypes[lineNum] := "empty"
                    lineNum++
                    lastLineWasEmpty := true
                }

                ; 表数组
                for i, item in value {
                    this.rawLines[lineNum] := "[[" key "]]"
                    this.lineTypes[lineNum] := "array-section"
                    lineNum++
                    lastLineWasEmpty := false

                    ; 生成缩进字符串
                    indentStr := ""
                    loop this.formatOptions.tableArrayItemIndent
                        indentStr .= " "

                    ; 添加表数组项中的键值对
                    for subKey, subValue in item {
                        this.rawLines[lineNum] := indentStr . subKey " = " this.FormatValue(subValue)
                        this.lineTypes[lineNum] := "key-value"
                        this.lineMapping[key "." i "." subKey] := lineNum
                        lineNum++
                    }

                    ; 根据配置决定是否添加空行
                    if (this.formatOptions.emptyLinesAfterArrayItems) {
                        this.rawLines[lineNum] := ""
                        this.lineTypes[lineNum] := "empty"
                        lineNum++
                        lastLineWasEmpty := true
                    }
                }
            }
        }
    }

    ; 添加一个类内部的方法来获取嵌套值
    GetNestedValueFromPath(data, path) {
        if (path.Length == 1)
            return data.Has(path[1]) ? data[path[1]] : ""

        if (data.Has(path[1]) && IsObject(data[path[1]])) {
            if (path.Length == 2)
                return data[path[1]].Has(path[2]) ? data[path[1]][path[2]] : ""

            currentMap := data[path[1]]
            loop path.Length - 2 {
                idx := A_Index + 1
                if (!currentMap.Has(path[idx]) || !IsObject(currentMap[path[idx]]))
                    return ""
                currentMap := currentMap[path[idx]]
            }
            return currentMap.Has(path[path.Length]) ? currentMap[path[path.Length]] : ""
        }

        return ""
    }

    DumpToString() {
        ; 首先收集所有行并按行号排序
        allLines := []
        maxLine := 0
        for lineNum in this.rawLines {
            maxLine := Max(maxLine, lineNum)
        }

        ; 收集所有行
        loop maxLine {
            lineNum := A_Index
            if (this.lineTypes.Has(lineNum)) {
                allLines.Push({
                    lineNum: lineNum,
                    content: this.rawLines[lineNum],
                    type: this.lineTypes[lineNum]
                })
            }
        }

        ; 处理嵌套表的空行问题
        finalContent := []
        lastWasSection := false
        lastSectionPath := ""
        skipNextEmptyLine := false
        lastWasNestedSection := false  ; 添加标记，记录上一行是否是嵌套表

        for i, lineInfo in allLines {
            ; 更新键值对的内容
            if (lineInfo.type == "key-value") {
                lineInfo.content := this.UpdateKeyValueLine(lineInfo.lineNum, lineInfo.content)
            }

            ; 处理空行
            if (lineInfo.type == "empty") {
                ; 如果需要跳过空行，则跳过
                if (skipNextEmptyLine) {
                    skipNextEmptyLine := false
                    continue
                }

                ; 避免文件开头的空行
                if (finalContent.Length == 0) {
                    continue
                }

                ; 避免连续空行
                if (finalContent.Length > 0 && finalContent[finalContent.Length] == "") {
                    continue
                }

                ; 检查下一行是否是表头，如果是，检查是否是嵌套表
                if (i < allLines.Length && (allLines[i + 1].type == "section" || allLines[i + 1].type ==
                    "array-section")) {
                    ; 如果下一行是表头
                    if (allLines[i + 1].type == "section") {
                        nextSectionPath := Trim(SubStr(allLines[i + 1].content, 2, StrLen(allLines[i + 1].content) - 2))

                        ; 检查是否是任何已知表的子表
                        isChildOfAnyTable := false
                        for j, content in finalContent {
                            if (SubStr(content, 1, 1) == "[" && SubStr(content, -1) == "]" && !InStr(content, "[[")) {
                                tablePath := Trim(SubStr(content, 2, StrLen(content) - 2))
                                if (InStr(nextSectionPath, tablePath ".") == 1) {
                                    isChildOfAnyTable := true
                                    break
                                }
                            }
                        }

                        ; 如果是子表，跳过空行
                        if (isChildOfAnyTable) {
                            continue
                        }
                    }
                }

                finalContent.Push("")
                continue
            }

            ; 处理表头
            if (lineInfo.type == "section") {
                ; 提取表路径
                sectionPath := Trim(SubStr(lineInfo.content, 2, StrLen(lineInfo.content) - 2))

                ; 检查是否是任何已知表的子表
                isChildTable := false
                for j, content in finalContent {
                    if (SubStr(content, 1, 1) == "[" && SubStr(content, -1) == "]" && !InStr(content, "[[")) {
                        tablePath := Trim(SubStr(content, 2, StrLen(content) - 2))
                        if (InStr(sectionPath, tablePath ".") == 1) {
                            isChildTable := true
                            break
                        }
                    }
                }

                ; 如果是子表，不添加空行
                if (isChildTable) {
                    skipNextEmptyLine := true
                } else if (finalContent.Length > 0 && finalContent[finalContent.Length] != "") {
                    ; 不是子表，如果最后一行不是空行，添加一个空行
                    finalContent.Push("")
                }

                finalContent.Push(lineInfo.content)
                lastWasSection := true
                lastWasNestedSection := InStr(sectionPath, ".") > 0  ; 记录是否是嵌套表
                lastSectionPath := sectionPath
                continue
            }

            ; 处理表数组
            if (lineInfo.type == "array-section") {
                ; 根据配置决定是否在表数组前添加空行
                if (this.formatOptions.emptyLinesBetweenSections) {
                    if ((lastWasNestedSection || !lastWasNestedSection) &&
                    finalContent.Length > 0 &&
                    finalContent[finalContent.Length] != "") {
                        finalContent.Push("")
                    }
                }

                finalContent.Push(lineInfo.content)
                lastWasSection := true
                lastWasNestedSection := false
                lastSectionPath := Trim(SubStr(lineInfo.content, 3, StrLen(lineInfo.content) - 4))
                continue
            }

            ; 处理其他类型的行
            finalContent.Push(lineInfo.content)
            lastWasSection := false
            lastWasNestedSection := false
            lastSectionPath := ""
        }

        ; 确保文件末尾有一个空行
        if (finalContent.Length > 0 && finalContent[finalContent.Length] != "") {
            finalContent.Push("")
        }

        return StrJoin(finalContent, "`n")
    }

    UpdateKeyValueLine(lineNum, originalLine) {
        ; 保持原始缩进和注释
        parts := StrSplit(originalLine, "=", , 2)
        key := Trim(parts[1])

        ; 提取前导空格
        leadingSpace := ""
        loop parse, originalLine {
            if (A_LoopField == " " || A_LoopField == "`t")
                leadingSpace .= A_LoopField
            else
                break
        }

        ; 提取等号周围的空格
        equalsSpaceBefore := ""
        equalsSpaceAfter := ""
        if (RegExMatch(originalLine, "(\s*)=(\s*)", &match)) {
            equalsSpaceBefore := match[1]
            equalsSpaceAfter := match[2]
        }

        ; 提取行内注释
        comment := ""
        if (InStr(parts[2], "#")) {
            commentParts := StrSplit(parts[2], "#", , 2)
            comment := "#" commentParts[2]
        }

        ; 获取新值
        value := ""
        found := false

        ; 查找当前行对应的映射
        for mappingKey, mappedLineNum in this.lineMapping {
            if (mappedLineNum == lineNum) {
                ; 找到了映射，解析键路径
                keyParts := StrSplit(mappingKey, ".")

                if (keyParts.Length == 1) {
                    ; 顶级键
                    if (this.data.Has(keyParts[1])) {
                        value := this.data[keyParts[1]]
                        found := true
                    }
                } else if (keyParts.Length >= 2) {
                    if (keyParts.Length == 3 && IsInteger(keyParts[2])) {
                        ; 表数组项
                        sectionName := keyParts[1]
                        arrayIndex := Integer(keyParts[2])
                        itemKey := keyParts[3]

                        if (this.data.Has(sectionName) &&
                        this.data[sectionName].Length >= arrayIndex &&
                        this.data[sectionName][arrayIndex].Has(itemKey)) {
                            value := this.data[sectionName][arrayIndex][itemKey]
                            found := true
                        }
                    } else {
                        ; 嵌套表或普通表
                        sectionName := keyParts[1]
                        if (keyParts.Length == 2) {
                            ; 普通表
                            if (this.data.Has(sectionName) && this.data[sectionName].Has(keyParts[2])) {
                                value := this.data[sectionName][keyParts[2]]
                                found := true
                            }
                        } else {
                            ; 嵌套表
                            nestedValue := this.GetNestedValueFromPath(this.data, keyParts)
                            if (nestedValue != "") {
                                value := nestedValue
                                found := true
                            }
                        }
                    }
                }
                break
            }
        }

        ; 如果没找到，尝试从原始行解析值
        if (!found) {
            originalValue := Trim(parts[2])
            if (InStr(originalValue, "#")) {
                originalValue := Trim(SubStr(originalValue, 1, InStr(originalValue, "#") - 1))
            }
            value := this.ParseValue(originalValue)
        }

        ; 重建行，保持原始格式
        return leadingSpace key equalsSpaceBefore "=" equalsSpaceAfter this.FormatValue(value) (comment ? " " comment :
            "")
    }

    ; 添加设置格式化选项的方法
    SetFormatOption(option, value) {
        if (this.formatOptions.HasOwnProp(option))
            this.formatOptions[option] := value
        return this
    }

    FormatValue(value, indent := 0) {
        if (value is Array) {
            if (value.Length == 0)
                return "[]"

            elements := []
            useMultiline := false

            ; 检查是否需要多行格式
            for element in value {
                if (IsObject(element) && !(element is String))
                    useMultiline := true
            }

            if (useMultiline && this.formatOptions.arrayIndent) {
                ; 多行格式
                result := "[\n"
                indentStr := ""
                loop indent + this.formatOptions.indentSize
                    indentStr .= " "

                for element in value {
                    result .= indentStr . this.FormatValue(element, indent + this.formatOptions.indentSize) . ",\n"
                }

                closeIndent := ""
                loop indent
                    closeIndent .= " "

                result .= closeIndent . "]"
                return result
            } else {
                ; 单行格式
                for element in value {
                    elements.Push(this.FormatValue(element))
                }
                return "[" . StrJoin(elements, ", ") . "]"
            }
        }

        if (value is String)
            return Chr(34) value Chr(34)

        if (value is Integer || value is Float)
            return value

        if (value = true)
            return "true"
        if (value = false)
            return "false"

        ; 如果是Map，不应该直接格式化
        if (value is Map)
            return Chr(34) "Object" Chr(34)

        return Chr(34) value Chr(34)
    }

    CollectNestedStructures(data, prefix, result, includeEmpty := false) {
        for key, value in data {
            if (IsObject(value) && !(value is Array)) {
                newPrefix := prefix ? prefix "." key : key

                ; 检查是否已经存在该表
                if (!this.HasSection(newPrefix)) {
                    ; 检查是否有键值对或嵌套对象
                    hasValues := false
                    hasNestedObjects := false
                    for subKey, subValue in value {
                        if (!IsObject(subValue) || (subValue is Array)) {
                            hasValues := true
                        } else if (IsObject(subValue) && !(subValue is Array)) {
                            hasNestedObjects := true
                        }
                    }

                    ; 根据参数决定是否包含没有键值对的表
                    if (hasValues || (includeEmpty && hasNestedObjects)) {
                        result[newPrefix] := value
                    }
                }

                ; 递归处理更深层的嵌套
                this.CollectNestedStructures(value, newPrefix, result, includeEmpty)
            }
        }
    }
}

StrJoin(array, delimiter := "") {
    result := ""
    for index, element in array {
        if (index > 1)
            result .= delimiter
        result .= element
    }
    return result
}

toml_read(file) {
    try {
        temp := TOML()
        temp.LoadFile(file)
        return temp.data
    } catch Error as err {
        throw Error("TOML 解析错误(toml_read): " err.Message, -1)
    }
}

toml_write(file, data) {
    temp := TOML()

    ; 如果存在原文件，先读取其注释和结构信息
    if (FileExist(file)) {
        originalToml := TOML()
        originalToml.LoadFile(file)
        ; 复制原始文件的结构信息
        temp.rawLines := originalToml.rawLines.Clone()
        temp.lineTypes := originalToml.lineTypes.Clone()
        temp.lineMapping := originalToml.lineMapping.Clone()
        temp.comments := originalToml.comments.Clone()
        temp.keyComments := originalToml.keyComments.Clone()
        temp.keyOrder := originalToml.keyOrder.Clone()
        temp.sectionOrder := originalToml.sectionOrder.Clone()
        temp.sectionKeyOrder := originalToml.sectionKeyOrder.Clone()
    }

    ; 更新数据
    temp.data := data

    ; 手动处理嵌套表结构
    ProcessNestedStructures(temp)

    ; 保存文件前先备份
    if (FileExist(file)) {
        try {
            FileCopy file, file ".bak", 1
        }
    }

    ; 保存新内容
    temp.SaveToFile(file)

    ; 验证新文件是否写入成功
    if (FileExist(file)) {
        fileContent := FileRead(file, "UTF-8")
        if (fileContent == "") {
            ; 如果新文件为空，还原备份
            if (FileExist(file ".bak")) {
                FileMove file ".bak", file, 1
                throw Error("写入失败，已还原备份文件")
            }
        } else {
            ; 写入成功，删除备份
            if (FileExist(file ".bak"))
                FileDelete file ".bak"
        }
    }
}

; 手动处理嵌套表结构
ProcessNestedStructures(tomlObj) {
    ; 获取当前最大行号
    maxLine := 0
    for lineNum in tomlObj.rawLines {
        maxLine := Max(maxLine, lineNum)
    }
    lineNum := maxLine + 1

    ; 首先处理顶级键值对
    hasTopLevelKeys := false
    lastLineWasEmpty := false

    for key, value in tomlObj.data {
        if (!IsObject(value) || (value is Array && !(value.Length > 0 && IsObject(value[1])))) {
            ; 检查该键是否已存在于映射中
            keyExists := false
            for mappingKey, _ in tomlObj.lineMapping {
                if (mappingKey == key) {
                    keyExists := true
                    break
                }
            }

            ; 如果键不存在，添加它
            if (!keyExists) {
                tomlObj.rawLines[lineNum] := key " = " tomlObj.FormatValue(value)
                tomlObj.lineTypes[lineNum] := "key-value"
                tomlObj.lineMapping[key] := lineNum
                lineNum++
                hasTopLevelKeys := true
                lastLineWasEmpty := false
            }
        }
    }

    ; 如果添加了顶级键，再添加一个空行（但避免连续空行）
    if (hasTopLevelKeys && !lastLineWasEmpty) {
        tomlObj.rawLines[lineNum] := ""
        tomlObj.lineTypes[lineNum] := "empty"
        lineNum++
        lastLineWasEmpty := true
    }

    ; 收集所有需要处理的嵌套表结构
    nestedStructures := Map()
    tomlObj.CollectNestedStructures(tomlObj.data, "", nestedStructures)

    ; 按照路径深度排序嵌套表
    nestedPaths := []
    for path in nestedStructures {
        nestedPaths.Push(path)
    }

    ; 使用自定义排序函数
    SortArray(nestedPaths)

    ; 处理每个嵌套表结构
    prevTablePrefix := ""
    for _, fullPath in nestedPaths {
        tableData := nestedStructures[fullPath]

        ; 跳过已存在的表
        if (tomlObj.HasSection(fullPath)) {
            continue
        }

        ; 分割路径
        parts := StrSplit(fullPath, ".")

        ; 检查是否是连续的嵌套表
        isContinuousNesting := false
        if (prevTablePrefix && InStr(fullPath, prevTablePrefix ".") == 1) {
            isContinuousNesting := true
        }

        ; 确保父表存在
        currentPath := ""
        for i, part in parts {
            if (i == parts.Length) {
                ; 最后一级表，在后面处理
                continue
            }

            currentPath := currentPath ? currentPath "." part : part

            ; 如果父表不存在，创建它
            if (!tomlObj.HasSection(currentPath)) {
                ; 只有当不是连续的嵌套表时才添加空行
                if (!isContinuousNesting && !lastLineWasEmpty) {
                    tomlObj.rawLines[lineNum] := ""
                    tomlObj.lineTypes[lineNum] := "empty"
                    lineNum++
                    lastLineWasEmpty := true
                }

                ; 添加表头
                tomlObj.rawLines[lineNum] := "[" currentPath "]"
                tomlObj.lineTypes[lineNum] := "section"
                lineNum++
                lastLineWasEmpty := false
                prevTablePrefix := currentPath
            }
        }

        ; 添加当前表
        ; 只有当不是连续的嵌套表时才添加空行
        if (!isContinuousNesting && !lastLineWasEmpty) {
            tomlObj.rawLines[lineNum] := ""
            tomlObj.lineTypes[lineNum] := "empty"
            lineNum++
            lastLineWasEmpty := true
        }

        tomlObj.rawLines[lineNum] := "[" fullPath "]"
        tomlObj.lineTypes[lineNum] := "section"
        lineNum++
        lastLineWasEmpty := false
        prevTablePrefix := fullPath

        ; 添加键值对
        hasKeyValues := false
        for key, value in tableData {
            if (!IsObject(value) || (value is Array)) {
                tomlObj.rawLines[lineNum] := key " = " tomlObj.FormatValue(value)
                tomlObj.lineTypes[lineNum] := "key-value"
                tomlObj.lineMapping[fullPath "." key] := lineNum
                lineNum++
                hasKeyValues := true
                lastLineWasEmpty := false
            }
        }

        ; 只有当表中有键值对且不是连续嵌套表的最后一个时才添加空行
        if (hasKeyValues && !lastLineWasEmpty) {
            tomlObj.rawLines[lineNum] := ""
            tomlObj.lineTypes[lineNum] := "empty"
            lineNum++
            lastLineWasEmpty := true
        }
    }
}

; 添加自定义排序函数
SortArray(arr) {
    ; 预先计算每个路径的深度
    depths := Map()
    for i, path in arr {
        depths[path] := StrSplit(path, ".").Length
    }

    ; 冒泡排序按照路径深度排序
    n := arr.Length
    loop n - 1 {
        i := A_Index
        loop n - i {
            j := A_Index
            ; 使用预先计算的深度
            if (depths[arr[j]] > depths[arr[j + 1]]) {
                ; 交换元素
                temp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := temp
            }
        }
    }
    return arr
}
