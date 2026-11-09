// Native adaptation of Hitomi's dictionary/event subset and documented PSY interface.
// Original authors: Holonics, NAKAUE.T (Kawari). See Hitomi-BSD.txt.
import Foundation
import LegacyText
import ModuleProtocol

public final class HitomiSession {
    private var entries: [String: [HitomiEntry]] = [:]
    private var order: [String] = []
    private var resources: [String: [String]] = [:]
    private var instant: [String: [String]] = [:]
    private var state = HitomiState()
    private let stateURL: URL
    private var modern = false
    private var ignored = Set<String>()
    private var once = Set<String>()
    private struct Relation: Hashable { let first: String; let second: String }
    private var related = Set<Relation>()
    private struct Timer { let deadline: TimeInterval; let target: String }
    private var timers: [Timer] = []
    private var clock = Date()
    private var operations = 0
    private var outputBytes = 0
    private var resourceSnapshot: [String: [String]]?
    private var dateFormat = "%year年%month月%day日%hour時%minute分%second秒"
    private var wordSnapshot: [String: [String]]?

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let root = masterDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        stateURL = stateStoreURL ?? root.appending(path: "hitomi-native-state.json")
        func contents(_ relative: String) throws -> Data {
            let path = relative.replacingOccurrences(of: "\\", with: "/")
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(":"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw HitomiError.invalidDictionary("path") }
            let url = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"), let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024 else { throw HitomiError.invalidDictionary(path) }
            return try Data(contentsOf: url)
        }
        func read(_ path: String) throws -> String {
            guard let value = try Self.text(contents(path)) else { throw HitomiError.invalidDictionary("charset") }
            return value
        }
        modern = FileManager.default.fileExists(atPath: root.appending(path: "hitomi.ini").path)
        let text = try read(modern ? "hitomi.ini" : "kawari.ini")
        var files: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { throw HitomiError.invalidDictionary("config entry") }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "dict" {
                files.append(value)
            } else if key.hasPrefix("String.") {
                resources[String(key.dropFirst(7)), default: []].append(value)
            } else if key == "event.ignore" {
                ignored.formUnion(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            } else if !["Locale", "Charset", "Language", "randomseed", "debug", "Autosave.data"].contains(key), !key.hasPrefix("lex."), !key.hasPrefix("hpp.") {
                throw HitomiError.unsupportedSyntax("config: " + key)
            }
        }
        guard !files.isEmpty, files.count <= 1024 else { throw HitomiError.invalidDictionary("dict list") }
        var total = 0, processor = HitomiPreprocessor()
        for file in files {
            let data = try contents(file); total += data.count
            guard total <= 8 * 1024 * 1024 else { throw HitomiError.limitExceeded }
            for bytes in data.split(separator: 10, omittingEmptySubsequences: false) {
                let raw = Data(bytes.last == 13 ? bytes.dropLast() : bytes[...])
                let decoded = raw.starts(with: Data("!KAWA".utf8)) ? try HitomiCipher.decodeLine(raw) : raw
                guard let text = Self.text(decoded) else { throw HitomiError.invalidDictionary("dictionary charset") }
                let line = text.trimmingCharacters(in: .whitespaces)
                if try processor.consume(line) {
                    continue
                }
                if processor.active {
                    try register(line, filename: URL(fileURLWithPath: file.replacingOccurrences(of: "\\", with: "/")).lastPathComponent)
                }
            }
            try processor.finishFile()
        }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard let size = try stateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024 else { throw HitomiError.limitExceeded }
            state = try JSONDecoder().decode(HitomiState.self, from: Data(contentsOf: stateURL))
            guard state.schemaVersion == 1, state.counters.count <= 16384, state.savedWords.count <= 16384, (state.resources?.count ?? 0) <= 16384,
                  state.hearts.words.count <= 16384, state.hearts.order.count <= 16384,
                  state.hearts.words.values.allSatisfy({ record in
                      ["Myself", "Master", "Friends", "Word", "Short"].contains(record.kind) && (-1000 ... 1000).contains(record.score) && record.relations.count <= 16384 && record.relations.values.allSatisfy { (1 ... 1000).contains($0) }
                  }) else { throw HitomiError.invalidDictionary("state contents") }
        } else {
            if FileManager.default.fileExists(atPath: root.appending(path: "hitomi.dat").path) {
                for line in try read("hitomi.dat").components(separatedBy: .newlines) {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if key.hasPrefix("Counter."), let number = Int64(value) {
                        state.counters[String(key.dropFirst(8))] = number
                    }
                    if key.hasPrefix("Word.") {
                        state.savedWords[String(key.dropFirst(5))] = [value]
                    }
                    if key.hasPrefix("String.") {
                        if state.resources == nil {
                            state.resources = [:]
                        }
                        guard state.resources!.count < 16384 else { throw HitomiError.limitExceeded }
                        state.resources![String(key.dropFirst(7))] = [value]
                    }
                }
            }
            if FileManager.default.fileExists(atPath: root.appending(path: "psy.ini").path) {
                for line in try read("psy.ini").components(separatedBy: .newlines) {
                    guard let colon = line.firstIndex(of: ":"), !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if key == "Hearts.dict" {
                        try state.hearts.load(read(value))
                    } else if !key.hasPrefix("Hearts.Short."), key != "dateForm" {
                        throw HitomiError.unsupportedSyntax("psy.ini: " + key)
                    }
                }
            }
        }
        if FileManager.default.fileExists(atPath: root.appending(path: "psy.ini").path) {
            for line in try read("psy.ini").components(separatedBy: .newlines) {
                guard let colon = line.firstIndex(of: ":"), line[..<colon].trimmingCharacters(in: .whitespaces) == "dateForm" else { continue }
                dateFormat = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        if let imported = state.resources {
            resources.merge(imported) { _, saved in saved }
        }
    }

    private static func text(_ data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8) ?? LegacyTextDecoder.decode(data, preferredCharset: "Shift_JIS")?.replacingOccurrences(of: "¥", with: "\\")
    }

    private func register(_ line: String, filename: String) throws {
        if line.isEmpty || line.hasPrefix(":") {
            return
        }
        guard line.utf8.count <= 1024 * 1024 else { throw HitomiError.limitExceeded }
        let fields = try HitomiSyntax.split(line, on: [":"])
        guard fields.count >= 2 else { throw HitomiError.unsupportedSyntax("dictionary entry") }
        let head = try HitomiSyntax.split(fields[0], on: ["&"])
        if head.count > 1 || line.contains("?#") || line.range(of: #"\$[A-Za-z]"#, options: .regularExpression) != nil {
            modern = true
        }
        let keyAndOption = try HitomiSyntax.split(head[0], on: [], whitespace: true)
        guard let keys = keyAndOption.first, keyAndOption.count <= 2 else { throw HitomiError.invalidDictionary("entry key") }
        let keyword = keyAndOption.count == 2 ? keyAndOption[1] : nil
        for condition in head.dropFirst() {
            let tokens = try HitomiSyntax.split(condition, on: [], whitespace: true)
            let allowed = ["exist", "empty", "has", "notHas", "found", "notFound", "==", "!=", ">", "<", ">=", "<="]
            guard (1 ... 3).contains(tokens.count), tokens[0].hasPrefix("$"), tokens.count == 1 || allowed.contains(tokens[1]) else { throw HitomiError.unsupportedSyntax("condition") }
        }
        let value = fields.dropFirst().joined(separator: ":")
        let values = try HitomiSyntax.split(value, on: [","]).map { part in
            (HitomiSyntax.literal(part) ?? part).replacingOccurrences(of: "${@", with: "${" + filename + "@")
        }.filter { !$0.isEmpty }
        for rawKey in keys.components(separatedBy: ",") {
            let key = rawKey.hasPrefix("@") ? filename + rawKey : rawKey
            guard !key.isEmpty, !key.hasPrefix("!"), !key.contains("${"), entries.count < 32768 else { throw HitomiError.invalidDictionary("entry key") }
            if entries[key] == nil {
                order.append(key)
            }
            entries[key, default: []].append(.init(values: values, conditions: Array(head.dropFirst()), keyword: keyword.flatMap(HitomiSyntax.literal) ?? keyword, isDefault: keyword == "."))
        }
    }

    public func request(_ request: ShioriRequest, charset: String = "UTF-8", now: Date = Date()) throws -> ShioriResponse {
        operations = 0; outputBytes = 0; instant = [:]; clock = now
        let beforeResources = resources, beforeTimers = timers
        let before = state, beforeOnce = once, beforeRelated = related
        wordSnapshot = state.savedWords; resourceSnapshot = resources
        defer { instant = [:]; wordSnapshot = nil; resourceSnapshot = nil }
        do {
            for i in 0 ... 7 {
                instant["!Reference\(i)"] = (request.reference(i) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            let id = request.id ?? ""
            instant["!keyword"] = instant["!Reference0"]
            if modern, id.hasPrefix("OnMouse") {
                instant["!keyword"] = [request.reference(4).flatMap { $0.isEmpty ? nil : $0 } ?? "."]
            }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
            for (key, number) in ["year": parts.year, "mon": parts.month, "month": parts.month, "day": parts.day, "hour": parts.hour, "minute": parts.minute, "second": parts.second, "week": parts.weekday.map { $0 - 1 }] {
                instant["!" + key] = [String(number ?? 0)]
            }
            let value: String?
            var status = 200
            if ignored.contains(id) {
                value = nil
            } else if id == "OnTeach", modern {
                let study = try teach(request)
                value = study.0; status = study.1
            } else if modern, id == "OnSecondChange", let index = timers.firstIndex(where: { $0.deadline < now.timeIntervalSince1970.rounded(.down) }) {
                let timer = timers.remove(at: index)
                value = try pick("?" + timer.target, depth: 0)
            } else if let resource = resources[id]?.randomElement() {
                value = resource
            } else if id == "OnAITalk" {
                value = try pick(entries["?#HitomiAITalk"] != nil ? "?#HitomiAITalk" : entries["?OnAITalk"] != nil ? "?OnAITalk" : "sentence", depth: 0)
            } else if id == "OnCommunicate" {
                value = try communicate(request.reference(1) ?? "")
            } else {
                value = try pick(entries["?" + id] != nil ? "?" + id : "?#" + id, depth: 0)
            }
            if state != before {
                try persist()
            }
            return response(value, status: status, charset: charset, notify: request.method == "NOTIFY")
        } catch { timers = beforeTimers; resources = beforeResources; state = before; once = beforeOnce; related = beforeRelated; throw error }
    }

    private func response(_ value: String?, status: Int, charset: String, notify: Bool = false) -> ShioriResponse {
        let hasValue = value?.isEmpty == false && !notify
        var headers = ShioriHeaders([.init(name: "Charset", value: charset)])
        if hasValue, let value {
            headers.append(name: "Value", value: value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))
        }
        let code = notify ? 204 : status != 200 ? status : hasValue ? 200 : 204
        return .init(statusCode: code, reasonPhrase: code == 200 ? "OK" : code == 311 ? "Not Enough" : code == 312 ? "Advice" : "No Content", headers: headers)
    }

    private func teach(_ request: ShioriRequest) throws -> (String?, Int) {
        guard let word = request.reference(0), !word.isEmpty else { return (nil, 204) }
        guard word.utf8.count <= 4096 else { throw HitomiError.limitExceeded }
        var history: [String] = []
        for index in 1 ... 64 {
            guard let value = request.reference(index) else { break }
            guard value.utf8.count <= 4096 else { throw HitomiError.limitExceeded }
            history.append(value)
        }
        guard request.reference(65) == nil else { throw HitomiError.limitExceeded }
        instant["!keyword"] = [word]
        instant["!teachword"] = history.last.map { $0.isEmpty ? [] : [$0] } ?? []
        instant["!teachedwords"] = Array(history.dropLast())
        instant["!relation"] = Array(state.hearts.words[word]?.relations.keys ?? [String: Int]().keys)
        let callback: String, status: Int
        if history.isEmpty {
            callback = state.hearts.words[word] == nil ? "NewWord" : "Require"; status = 311
        } else if let latest = history.last, latest.isEmpty {
            var seen = Set<String>()
            let known = history.dropLast().filter { !$0.isEmpty && $0 != word && state.hearts.words[$0] != nil && seen.insert($0).inserted }
            let fresh = known.filter { related.insert(Relation(first: min(word, $0), second: max(word, $0))).inserted }
            try state.hearts.study(word, related: fresh)
            callback = "Commit"; status = 200
        } else if history.last == word {
            callback = "SameKey"; status = 312
        } else if history.last.flatMap({ state.hearts.words[$0] }) == nil {
            callback = "Reject"; status = 311
        } else {
            callback = "Require"; status = 311
        }
        return try (pick("?#HitomiStudy" + callback, depth: 0), status)
    }

    private func communicate(_ sentence: String) throws -> String? {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        instant["!Scripts"] = [text]; instant["!keyword"] = []
        if modern {
            let known = state.hearts.order.filter { !$0.isEmpty && text.contains($0) }
            instant["!instant"] = known
            instant["!like"] = known.filter { (state.hearts.words[$0]?.score ?? 0) > 0 }
            instant["!dislike"] = known.filter { (state.hearts.words[$0]?.score ?? 0) < 0 }
            if instant["!like"]?.isEmpty == false, let value = try pick("?like", depth: 0) {
                return value
            }
            if instant["!dislike"]?.isEmpty == false, let value = try pick("?dislike", depth: 0) {
                return value
            }
            if let value = try pick("?sentence", depth: 0) {
                return value
            }
        }
        if text.isEmpty {
            return try pick(modern ? "?#silence" : "?silence", depth: 0)
        }
        if entries["?" + text] != nil {
            return try pick("?" + text, depth: 0)
        }
        for key in order where key.hasPrefix("?") && key.count > 1 {
            let keyword = String(key.dropFirst())
            if !keyword.hasPrefix("#"), text.contains(keyword) {
                return try pick(key, depth: 0)
            }
        }
        instant["!instant"] = [text]
        return try pick(modern ? "?#switch" : "?switch", depth: 0)
    }

    private func budget(_ depth: Int) throws {
        operations += 1
        guard depth <= 30, operations <= 20000 else { throw HitomiError.limitExceeded }
    }

    private func candidates(_ key: String, depth: Int) throws -> [String] {
        try budget(depth)
        if let value = instant[key] {
            return value
        }
        if key.hasPrefix("~String.") {
            return (resourceSnapshot ?? resources)[String(key.dropFirst(8))] ?? []
        }
        if key == "username", let value = (resourceSnapshot ?? resources)["username"] {
            return value
        }
        if key.hasPrefix("~Word.") {
            return (wordSnapshot ?? state.savedWords)[String(key.dropFirst(6))] ?? []
        }
        if key.hasPrefix("?%"), once.contains(key) {
            return []
        }
        var normal: [String] = [], fallback: [String] = []
        for entry in entries[key] ?? [] {
            if let keyword = entry.keyword, !entry.isDefault, !(instant["!keyword"] ?? []).contains(keyword) {
                continue
            }
            var match = true
            for condition in entry.conditions where match {
                match = try test(condition, depth: depth + 1)
            }
            if match {
                if entry.isDefault {
                    fallback += entry.values
                } else {
                    normal += entry.values
                }
            }
        }
        return normal.isEmpty ? fallback : normal
    }

    private func pick(_ key: String, depth: Int) throws -> String? {
        guard let value = try candidates(key, depth: depth).randomElement() else { return nil }
        if key.hasPrefix("?%") {
            once.insert(key)
        }
        return try expand(value, depth: depth + 1)
    }

    private func list(_ source: String, depth: Int) throws -> [String] {
        try budget(depth)
        let union = try HitomiSyntax.split(source, on: ["|"])
        let intersection = try HitomiSyntax.split(source, on: ["&"])
        guard !(union.count > 1 && intersection.count > 1) else { throw HitomiError.unsupportedSyntax("mixed list operators") }
        let separator: Character = union.count > 1 ? "|" : intersection.count > 1 ? "&" : ","
        let parts = try HitomiSyntax.split(source, on: [separator])
        if separator != ",", parts.contains(where: { (try? HitomiSyntax.split($0, on: [","]))?.count != 1 }) {
            throw HitomiError.unsupportedSyntax("mixed list operators")
        }
        var result: [String] = [], initialized = false
        for part in parts {
            if part.isEmpty {
                continue
            }
            let values: [String]
            if let literal = HitomiSyntax.literal(part) {
                values = [literal]
            } else if let data = dataValues(part) {
                values = data
            } else {
                let raw = try candidates(part, depth: depth + 1)
                if separator == "," {
                    values = try raw.map { try expand($0, depth: depth + 1) }
                } else {
                    values = try flatten(part, visited: [], depth: depth + 1)
                }
            }
            if separator == "&", initialized {
                result = result.filter { values.contains($0) }
            } else {
                result += values
            }
            initialized = true
            guard result.count <= 16384 else { throw HitomiError.limitExceeded }
        }
        if separator != "," {
            var seen = Set<String>(); result = result.filter { seen.insert($0).inserted }
        }
        return result
    }

    private func dataValues(_ key: String) -> [String]? {
        // Incoming text and saved atoms are data, never another PSY program.
        if key.hasPrefix("!") {
            return instant[key] ?? []
        }
        if key.hasPrefix("~String.") {
            return (resourceSnapshot ?? resources)[String(key.dropFirst(8))] ?? []
        }
        if key == "username", let value = (resourceSnapshot ?? resources)["username"] {
            return value
        }
        if key.hasPrefix("~Word.") {
            return (wordSnapshot ?? state.savedWords)[String(key.dropFirst(6))] ?? []
        }
        return nil
    }

    private func flatten(_ key: String, visited: Set<String>, depth: Int) throws -> [String] {
        try budget(depth)
        if let data = dataValues(key) {
            return data
        }
        guard !visited.contains(key) else { throw HitomiError.limitExceeded }
        var visited = visited; visited.insert(key)
        var result: [String] = []
        for value in try candidates(key, depth: depth + 1) {
            if let body = HitomiSyntax.body(value), !body.contains(where: { ",|&\"".contains($0) }) {
                result += try flatten(body, visited: visited, depth: depth + 1)
            } else {
                try result.append(expand(value, depth: depth + 1))
            }
            guard result.count <= 16384 else { throw HitomiError.limitExceeded }
        }
        return result
    }

    private func operand(_ source: String, depth: Int) throws -> [String] {
        if let body = HitomiSyntax.body(source) {
            return try list(body, depth: depth + 1)
        }
        if let literal = HitomiSyntax.literal(source) {
            return [literal]
        }
        if source.hasPrefix("$") {
            return try evaluateCall(source, depth: depth + 1)
        }
        return [source]
    }

    private func test(_ source: String, depth: Int) throws -> Bool {
        let tokens = try HitomiSyntax.split(source, on: [], whitespace: true)
        guard let lhs = tokens.first, lhs.hasPrefix("${") || lhs.hasPrefix("$") else { throw HitomiError.unsupportedSyntax("condition left operand") }
        let left = try operand(lhs, depth: depth + 1)
        if tokens.count == 1 {
            return !left.isEmpty
        }
        let op = tokens[1]
        if tokens.count == 2 {
            if op == "exist" {
                return !left.isEmpty
            }
            if op == "empty" {
                return left.isEmpty
            }
            throw HitomiError.unsupportedSyntax("condition operator: " + op)
        }
        guard tokens.count == 3 else { throw HitomiError.invalidDictionary("condition") }
        let right = try operand(tokens[2], depth: depth + 1)
        switch op {
        case "has": return right.allSatisfy { left.contains($0) }
        case "notHas": return !right.allSatisfy { left.contains($0) }
        case "found": return left.contains { a in right.contains { a.contains($0) } }
        case "notFound": return !left.contains { a in right.contains { a.contains($0) } }
        case "==", "!=", ">", "<", ">=", "<=":
            return left.contains { a in right.contains { b in
                guard let x = Int64(a), let y = Int64(b) else { return false }
                return op == "==" ? x == y : op == "!=" ? x != y : op == ">" ? x > y : op == "<" ? x < y : op == ">=" ? x >= y : x <= y
            } }
        default: throw HitomiError.unsupportedSyntax("condition operator: " + op)
        }
    }

    private func expand(_ source: String, depth: Int) throws -> String {
        try budget(depth)
        var output = "", local: [String] = [], cursor = source.startIndex
        while cursor < source.endIndex {
            if source[cursor] != "$" {
                output.append(source[cursor]); cursor = source.index(after: cursor); continue
            }
            let after = source.index(after: cursor)
            guard after < source.endIndex else { throw HitomiError.invalidDictionary("word reference") }
            var nameEnd = after
            while nameEnd < source.endIndex, source[nameEnd].isLetter || source[nameEnd].isNumber || "_.".contains(source[nameEnd]) {
                nameEnd = source.index(after: nameEnd)
            }
            if nameEnd < source.endIndex, source[nameEnd] == "{" {
                let end = try HitomiSyntax.callEnd(source, from: nameEnd)
                let body = String(source[source.index(after: nameEnd) ..< end])
                let result: String
                if nameEnd == after {
                    if let index = Int(body), index >= 0 {
                        result = local.indices.contains(index) ? local[index] : ""
                    } else if body.hasPrefix("?%") {
                        result = try pick(body, depth: depth + 1) ?? ""
                    } else {
                        result = try list(body, depth: depth + 1).randomElement() ?? (modern ? "" : body)
                        local.append(result)
                    }
                } else {
                    result = try execute(String(source[after ..< nameEnd]), arguments: list(body, depth: depth + 1), depth: depth + 1).randomElement() ?? ""
                    local.append(result)
                }
                output += result; cursor = source.index(after: end)
            } else {
                throw HitomiError.invalidDictionary("command argument list")
            }
            guard output.utf8.count <= 1024 * 1024 else { throw HitomiError.limitExceeded }
        }
        outputBytes += output.utf8.count
        guard outputBytes <= 8 * 1024 * 1024 else { throw HitomiError.limitExceeded }
        return output
    }

    private func evaluateCall(_ source: String, depth: Int) throws -> [String] {
        guard let brace = source.firstIndex(of: "{"), source.hasSuffix("}") else { throw HitomiError.invalidDictionary("command") }
        return try execute(String(source[source.index(after: source.startIndex) ..< brace]), arguments: list(String(source[source.index(after: brace) ..< source.index(before: source.endIndex)]), depth: depth + 1), depth: depth + 1)
    }

    private func execute(_ command: String, arguments args: [String], depth: Int) throws -> [String] {
        try budget(depth)
        let result: [String]
        switch command {
        case "GetVersion": result = ["PSY/1.0"]
        case "Join": result = args.isEmpty ? [] : [args.dropFirst().joined(separator: args[0])]
        case "Length": result = [String(args.count)]
        case "First": result = Array(args.prefix(1))
        case "Rest": result = Array(args.dropFirst())
        case "Get": result = args.first.map { [String(state.counters[$0] ?? 0)] } ?? []
        case "Inc", "Dec", "Reset":
            if let key = args.first {
                guard state.counters.count < 16384 else { throw HitomiError.limitExceeded }
                state.counters[key] = command == "Reset" ? 0 : (state.counters[key] ?? 0) &+ (command == "Inc" ? 1 : -1)
            }
            result = []
        case "SetWord":
            if let key = args.first {
                guard state.savedWords.count < 16384 else { throw HitomiError.limitExceeded }; state.savedWords[key] = Array(args.dropFirst())
            }
            result = []
        case "KillWords": for key in args {
                state.savedWords.removeValue(forKey: key)
            }; result = []
        case "Tmp": result = []
        case "SetTimer":
            if let delay = args.first.flatMap(Int.init), delay > 0 {
                guard timers.count < 1024 else { throw HitomiError.limitExceeded }
                var target = args.count > 1 ? args[1] : "#HitomiTimer"
                if target.isEmpty {
                    target = "#HitomiTimer"
                }
                if !target.hasPrefix("#") {
                    target = "#" + target
                }
                timers.append(.init(deadline: clock.timeIntervalSince1970.rounded(.down) + Double(delay), target: target))
            }
            result = []
        case "ResetTimer": timers.removeAll(); result = []
        case "UserName":
            if let name = args.first {
                resources["username"] = [name]
                if state.resources == nil {
                    state.resources = [:]
                }
                state.resources!["username"] = [name]
                if let ownName = state.hearts.order.first(where: { state.hearts.words[$0]?.kind == "Myself" }) {
                    try state.hearts.notify(ownName, name)
                }
            }
            result = []
        case "MakeDateString":
            guard args.count >= 6 else { return [] }
            var formatted = dateFormat
            for (key, value) in zip(["year", "month", "day", "hour", "minute", "second"], args) {
                formatted = formatted.replacingOccurrences(of: "%" + key, with: Int(value).map(String.init) ?? value)
            }
            result = [formatted]
        case "Hearts.Words.Append", "Hearts.Friends.Append": result = try state.hearts.append(args, friends: command.contains("Friends"))
        case "Hearts.Notify":
            if args.count >= 2 {
                try state.hearts.notify(args[0], args[1])
            }
            result = []
        case "Hearts.Set.Relation":
            if args.count >= 2 {
                let pair = Relation(first: min(args[0], args[1]), second: max(args[0], args[1]))
                if related.insert(pair).inserted {
                    try state.hearts.relate(args[0], args[1])
                }
            }
            result = []
        case "Hearts.Love", "Hearts.Hate": try state.hearts.preference(args, score: command == "Hearts.Love" ? 1000 : -1000); result = []
        case "Hearts.Exist", "Hearts.Exist.Words", "Hearts.Exist.Friends": result = args.filter { state.hearts.matches($0, filter: command.components(separatedBy: ".").dropFirst(2).first ?? "") }
        case "Hearts.Like", "Hearts.Like.Words", "Hearts.Like.Friends", "Hearts.Dislike", "Hearts.Dislike.Words", "Hearts.Dislike.Friends":
            let positive = command.contains(".Like"), filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            result = args.filter { state.hearts.matches($0, filter: filter) && (positive ? (state.hearts.words[$0]?.score ?? 0) > 0 : (state.hearts.words[$0]?.score ?? 0) < 0) }
        case "Hearts.Load", "Hearts.Load.Words", "Hearts.Load.Friends":
            let filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            result = state.hearts.order.filter { state.hearts.matches($0, filter: filter) }
        case "Hearts.Random", "Hearts.Random.Words", "Hearts.Random.Friends":
            let filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            result = state.hearts.order.filter { state.hearts.matches($0, filter: filter) }.randomElement().map { [$0] } ?? []
        case "Hearts.RelationHolder", "Hearts.RelationHolder.Words", "Hearts.RelationHolder.Friends":
            let filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            result = args.filter { state.hearts.matches($0, filter: filter) && !(state.hearts.words[$0]?.relations.isEmpty ?? true) }
        case "Hearts.CommonRelation", "Hearts.CommonRelation.Words", "Hearts.CommonRelation.Friends":
            let filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            var common = Set(args.first.flatMap { state.hearts.words[$0] }?.relations.keys.map(\.self) ?? [])
            for name in args.dropFirst() {
                common.formIntersection(state.hearts.words[name]?.relations.keys.map(\.self) ?? [])
            }
            result = args.count < 2 ? [] : state.hearts.order.filter { common.contains($0) && state.hearts.matches($0, filter: filter) }
        case "Hearts.Study":
            guard let name = args.first else { throw HitomiError.invalidDictionary("Hearts.Study arguments") }
            try state.hearts.study(name, related: Array(args.dropFirst()))
            result = state.hearts.order.filter { state.hearts.words[name]?.relations[$0] != nil }
        case "Hearts.Get.Relation", "Hearts.GetRelation", "Hearts.GetRelation.Words", "Hearts.GetRelation.Friends":
            let filter = command.components(separatedBy: ".").dropFirst(2).first ?? ""
            let related = Set(args.flatMap { Array(state.hearts.words[$0]?.relations.keys ?? [String: Int]().keys) })
            result = state.hearts.order.filter { related.contains($0) && state.hearts.matches($0, filter: filter) }
        default: throw HitomiError.unsupportedSyntax("PSY: " + command)
        }
        instant["!psy"] = result
        return result
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= 8 * 1024 * 1024 else { throw HitomiError.limitExceeded }
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stateURL, options: .atomic)
    }

    public func save() throws {
        if !state.counters.isEmpty || !state.savedWords.isEmpty || !state.hearts.words.isEmpty || state.resources?.isEmpty == false {
            try persist()
        }
    }
}
