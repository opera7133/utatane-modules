import Foundation
import LegacyText
import ModuleProtocol

public final class KonokaSession {
    private struct State: Codable {
        var variables: [String: String] = [:]
        var saved: [String: String] = [:]
        var learned: [String: [String]] = [:]
        enum CodingKeys: CodingKey { case saved, learned }
    }

    private var state = State()
    private var dictionary: KonokaDictionary
    private let stateURL: URL
    private var requestContext = ShioriRequest(method: "GET")
    private var now = Date()
    private var operations = 0
    private var names: [String: String] = [:]
    private var teachContext: [String: String]?
    private var dataValues: [(String, String)] = []

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        dictionary = try KonokaDictionary.load(masterDirectoryURL)
        stateURL = stateStoreURL ?? masterDirectoryURL.appending(path: "konoka-state.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard let size = try stateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024 else { throw KonokaError.limitExceeded }
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
        } else {
            let source = masterDirectoryURL.appending(path: "values.dat").resolvingSymlinksInPath().standardizedFileURL
            if FileManager.default.fileExists(atPath: source.path) {
                let root = masterDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
                guard source.path.hasPrefix(root.path + "/"), let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024,
                      let text = try LegacyTextDecoder.decode(Data(contentsOf: source)) else { throw KonokaError.invalidDictionary("values.dat") }
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    guard let comma = line.firstIndex(of: ","), comma != line.startIndex, state.saved.count < 16384 else { throw KonokaError.invalidDictionary("values.dat record") }
                    state.saved[String(line[..<comma])] = String(line[line.index(after: comma)...])
                }
            }
        }
        if let data = try? Data(contentsOf: masterDirectoryURL.appending(path: "descript.txt")), let text = LegacyTextDecoder.decode(data) {
            for line in text.components(separatedBy: .newlines) {
                let fields = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if fields.count == 2 {
                    names[fields[0].lowercased()] = fields[1]
                }
            }
        }
        operations = 0
        _ = try event("OnLoad", depth: 0)
    }

    public func request(_ request: ShioriRequest, charset: String = "UTF-8", now: Date = Date()) throws -> ShioriResponse {
        requestContext = request; self.now = now; operations = 0; dataValues = []; teachContext = nil
        let isTeach = request.id == "OnTeach"
        if isTeach {
            var context = ["word": request.reference(0) ?? "", "lastnum": "", "lasthint": ""]
            for index in 0 ..< 16 {
                guard let hint = request.reference(index + 1) else { break }
                context["hint\(index)"] = hint; context["lastnum"] = String(index); context["lasthint"] = hint
            }
            guard request.reference(17) == nil else { throw KonokaError.limitExceeded }
            teachContext = context
        }
        defer { teachContext = nil; dataValues = [] }
        let before = state
        do {
            var value: String? = if let id = request.id {
                if let resource = dictionary.resources[id]?.randomElement() {
                    try expand(resource, depth: 0)
                } else if id == "OnAITalk" {
                    try event("OnAITalk", depth: 0) ?? event("OnIntervalTalk", depth: 0) ?? randomTalk(depth: 0)
                } else if id == "OnCommunicate" {
                    try dictionary.responses.first(where: { (request.reference(1) ?? "").contains($0.0) }).map { try expand($0.1, depth: 0) }
                } else {
                    try event(id, depth: 0)
                }
            } else {
                nil
            }
            var status = 200
            if isTeach, var script = value {
                if script.contains("\\[shortage]") {
                    status = 311
                }
                if script.contains("\\[advice]") {
                    status = 312
                }
                if script.contains("\\[success]") {
                    status = 200
                }
                for flag in ["shortage", "advice", "success"] {
                    script = script.replacingOccurrences(of: "\\[\(flag)]", with: "")
                }
                value = script
            }
            value = try value.map { try restoreData($0) }
            if state.saved != before.saved || state.learned != before.learned {
                try persist()
            }
            let hasContent = value?.isEmpty == false && request.method != "NOTIFY"
            var headers = ShioriHeaders([.init(name: "Charset", value: charset)])
            if let value, hasContent {
                let isResource = request.id.flatMap { dictionary.resources[$0] } != nil
                let script = isResource || isTeach || value.hasSuffix("\\e") ? value : value + "\\e"
                headers.append(name: "Value", value: script.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))
            }
            let code = request.method == "NOTIFY" ? 204 : status != 200 ? status : hasContent ? 200 : 204
            return .init(statusCode: code, reasonPhrase: code == 311 ? "Not Enough" : code == 312 ? "Advice" : code == 200 ? "OK" : "No Content", headers: headers)
        } catch { state = before; throw error }
    }

    public func save() throws {
        operations = 0; dataValues = []; teachContext = nil
        let before = state
        do { _ = try event("OnUnload", depth: 0); try persist() }
        catch { state = before; throw error }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        guard data.count <= 8 * 1024 * 1024 else { throw KonokaError.limitExceeded }
        try data.write(to: stateURL, options: .atomic)
    }

    private func budget(_ depth: Int) throws {
        operations += 1
        guard depth <= 48, operations <= 10000 else { throw KonokaError.limitExceeded }
    }

    private func event(_ id: String, depth: Int) throws -> String? {
        try budget(depth)
        var matches: [String] = []
        for candidate in dictionary.events where candidate.id == id {
            if try candidate.condition.isEmpty || KonokaExpression.truth(expression(candidate.condition, depth: depth + 1)) {
                matches.append(candidate.script)
            }
        }
        guard let selected = matches.randomElement() else { return nil }
        if selected == "*" {
            return nil
        }
        let expanded = try expand(selected, depth: depth + 1)
        if expanded.hasPrefix("@") {
            return try event(String(expanded.dropFirst()), depth: depth + 1)
        }
        return expanded
    }

    private func randomTalk(depth: Int) throws -> String? {
        guard let value = dictionary.words.first(where: { $0.0 == "e" })?.1.randomElement() else { return nil }
        return try expand(value, depth: depth + 1)
    }

    private func read(_ name: String, depth _: Int) throws -> String? {
        if let value = teachContext?[name] {
            return value
        }
        if let value = state.variables[name] {
            return value
        }
        let words = (dictionary.words.first { $0.0 == name }?.1 ?? []) + (state.learned[name] ?? [])
        if let word = words.randomElement() {
            return word
        }
        if name.hasPrefix("ref"), let index = Int(name.dropFirst(3)) {
            return requestContext.reference(index) ?? ""
        }
        if name.hasPrefix("rand"), let digits = Int(name.dropFirst(4)), (1 ... 9).contains(digits) {
            return String(Int.random(in: 0 ..< Int(pow(10.0, Double(digits)))))
        }
        switch name {
        case "sender": return requestContext.headers["Sender"] ?? ""
        case "sentence": return requestContext.reference(1) ?? ""
        case "selfname", "selfname2": return names["sakura.name"] ?? names["name"]
        case "keroname": return names["kero.name"] ?? names["name2"]
        case "year", "month", "day", "hour", "minute", "second", "week":
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
            let values = ["year": parts.year, "month": parts.month, "day": parts.day, "hour": parts.hour, "minute": parts.minute, "second": parts.second, "week": parts.weekday.map { $0 - 1 }]
            return String(values[name]!!)
        default: return nil
        }
    }

    private func expression(_ source: String, depth: Int) throws -> String {
        try budget(depth)
        if source.hasPrefix("@") {
            return try event(String(source.dropFirst()), depth: depth + 1) ?? ""
        }
        // Percent references are substituted before evaluation; $ references read current state.
        let substituted = try expand(source, depth: depth + 1)
        var parser = try KonokaExpression(substituted, literal: { try self.restoreData($0) })
        return try KonokaExpression.evaluate(parser.parse(), read: { key in
            guard let value = try self.read(key, depth: depth + 1) else { return nil }
            return self.isData(key) ? value : try self.restoreData(self.expand(value, depth: depth + 1))
        }, write: { try self.assign($0, $1, depth: depth + 1) })
    }

    private func assign(_ name: String, _ value: String, depth: Int) throws -> String {
        try budget(depth)
        let value = try restoreData(value)
        let args = value.components(separatedBy: ".")
        let result: String
        switch name {
        case "_save":
            let pair = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return "" }
            state.saved[String(pair[0])] = String(pair[1]); result = String(pair[1])
        case "_load": result = state.saved[value] ?? ""
        case "_isval": result = state.variables[value] != nil || teachContext?[value] != nil ? "1" : "0"
        case "_get": result = teachContext?[value] ?? state.variables[value] ?? ""
        case "_wordtype":
            result = dictionary.words.first { $0.1.contains(value) || (state.learned[$0.0]?.contains(value) ?? false) }?.0 ?? state.learned.keys.sorted().first { state.learned[$0]?.contains(value) ?? false } ?? ""
        case "_length": result = String(value.lengthOfBytes(using: .shiftJIS))
        case "_upcase": result = value.uppercased()
        case "_locase": result = value.lowercased()
        case "_instr":
            if args.count >= 2, let range = args[0].range(of: args[1]) {
                result = String(args[0][..<range.lowerBound].lengthOfBytes(using: .shiftJIS) + 1)
            } else {
                result = "0"
            }
        case "_substr":
            guard args.count >= 2, let start = Int(args[1]), start >= 1, let bytes = LegacyTextDecoder.encode(args[0], charset: "Shift_JIS") else { return "" }
            let length = args.count >= 3 ? max(0, Int(args[2]) ?? 0) : bytes.count
            result = LegacyTextDecoder.decode(Data(bytes.dropFirst(min(start - 1, bytes.count)).prefix(length)), preferredCharset: "Shift_JIS") ?? ""
        case "_replace": result = args.count >= 3 && !args[1].isEmpty ? args[0].replacingOccurrences(of: args[1], with: args[2]) : value
        case "_registword":
            guard args.count >= 2 else { return "" }
            guard state.learned.count < 16384, (state.learned[args[0]]?.count ?? 0) < 16384, value.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            let word = args.dropFirst().joined(separator: ".")
            if !(dictionary.words.first { $0.0 == args[0] }?.1.contains(word) ?? false), !(state.learned[args[0]]?.contains(word) ?? false) {
                state.learned[args[0], default: []].append(word)
            }
            result = word
        case "_countword": result = String((dictionary.words.first { $0.0 == value }?.1.count ?? 0) + (state.learned[value]?.count ?? 0))
        case "_first": result = args[0].components(separatedBy: "\t").first ?? ""
        case "_rest": result = args[0].components(separatedBy: "\t").dropFirst().joined(separator: "\t")
        case "_listlen": result = String(args[0].components(separatedBy: "\t").count)
        case "_middle":
            let list = args[0].components(separatedBy: "\t"), index = args.count > 1 ? (Int(args[1]) ?? 0) : -1
            result = list.indices.contains(index) ? list[index] : ""
        case "timestamp", "_timestamp":
            let fields = value.split(separator: ",").compactMap { Int($0) }
            if fields.count >= 6 {
                result = name == "timestamp" ? "\(fields[0])年\(fields[1])月\(fields[2])日 \(fields[3])時\(fields[4])分\(fields[5])秒" : String(format: "%04d/%02d/%d %02d:%02d:%02d", fields[0], fields[1], fields[2], fields[3], fields[4], fields[5])
            } else {
                result = ""
            }
        default:
            if let template = dictionary.words.first(where: { $0.0 == name })?.1.randomElement() {
                return try expand(template.replacingOccurrences(of: "%argv%", with: try protectData(value)), depth: depth + 1)
            }
            result = value
        }
        let restored = try restoreData(result)
        guard state.variables.count < 16384, restored.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
        state.variables[name] = restored
        return restored
    }

    private func expand(_ source: String, depth: Int) throws -> String {
        try budget(depth)
        var output = source
        var cache: [String: String] = [:]
        var iteration = 0
        while iteration < 1000 {
            iteration += 1
            guard output.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            if let start = output.range(of: "%("), let end = closingParen(output, after: start.upperBound) {
                let body = String(output[start.upperBound ..< end])
                let result = try expression(body, depth: depth + 1)
                try output.replaceSubrange(start.lowerBound ... end, with: protectData(result))
                continue
            }
            var changed = false
            let keys = dictionary.words.map(\.0).filter { !["e", "ft", "hl", "re", "ch", "ev", "u", "id"].contains($0) } + state.variables.keys.sorted { $0.count > $1.count } + state.learned.keys.sorted() + (teachContext?.keys.sorted { $0.count > $1.count } ?? []) + (0 ... 7).map { "ref\($0)" } + ["year", "month", "day", "week", "hour", "minute", "second", "sender", "sentence", "selfname2", "selfname", "keroname"] + (1 ... 9).map { "rand\($0)" }
            for key in keys where output.contains("%" + key) {
                guard let value = try cache[key] ?? read(key, depth: depth + 1) else { continue }
                let replacement = isData(key) ? try protectData(value) : value
                cache[key] = value
                let replaced = output.replacingOccurrences(of: "%" + key, with: replacement)
                if replaced != output {
                    output = replaced; changed = true; break
                }
            }
            if output.contains("\\a"), let value = try randomTalk(depth: depth + 1) {
                output = output.replacingOccurrences(of: "\\a", with: value); changed = true
            }
            if !changed {
                return output
            }
        }
        throw KonokaError.limitExceeded
    }

    private func isData(_ key: String) -> Bool {
        state.variables[key] != nil || teachContext?[key] != nil || state.learned[key] != nil || key.hasPrefix("ref") || ["sender", "sentence", "selfname", "selfname2", "keroname", "year", "month", "day", "hour", "minute", "second", "week"].contains(key) || key.hasPrefix("rand")
    }

    private func protectData(_ value: String) throws -> String {
        guard value.utf8.count <= 1024 * 1024, dataValues.count < 4096 else { throw KonokaError.limitExceeded }
        let key = "KONOKA_DATA_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        dataValues.append((key, value)); return key
    }

    private func restoreData(_ source: String) throws -> String {
        var result = source
        for (key, value) in dataValues.reversed() where result.contains(key) {
            var count = 0, cursor = result.startIndex
            while let range = result.range(of: key, range: cursor ..< result.endIndex) {
                count += 1; cursor = range.upperBound
            }
            let size = result.utf8.count + count * (value.utf8.count - key.utf8.count)
            guard size <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    private func closingParen(_ source: String, after start: String.Index) -> String.Index? {
        var level = 1, quoted = false
        for i in source[start...].indices {
            if source[i] == "\"" {
                quoted.toggle()
            }
            if !quoted {
                if source[i] == "(" {
                    level += 1
                }
                if source[i] == ")" {
                    level -= 1; if level == 0 {
                        return i
                    }
                }
            }
        }
        return nil
    }
}
