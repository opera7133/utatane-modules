import Foundation
import LegacyText
import ModuleProtocol
import SaoriClient

public final class MaeSession {
    struct Tag {
        var name: String
        var condition: MaeExpr?
        var program: [MaeStatement]
        var sentences: [(Int, String)]
        var indices: [Int: Int] = [:]
        var remaining: [Int: [Int]] = [:]
    }
    struct News: Codable { var revision: Int32; var text: String; var date: Date }
    struct State: Codable { var variables: [String: MaeValue]; var configuration: [String: String]; var news: [String: [News]] }
    struct Word { let text: String; let part: String; let genre: String; let titles: [String]; let mood: Int }
    let directory: URL
    let stateURL: URL
    let vm = MaeInterpreter()
    let saori: DynamicSaoriRegistry
    var saoriPaths: [String: String] = [:]
    var tags: [Tag] = []
    var configuration = ["LOG": "0", "SHIORI": "3.0", "TALK_INTERVAL": "3", "TALK_INTERVAL_DETAIL": "0",
                         "TALK_INTERVAL_ADDITION": "30", "MIKIRE": "20", "KASANARI": "20", "SAWARI": "100",
                         "SECURITY_LEVEL": "8", "USERNAME": "", "UNDEFINED_WORD": "アレ", "MAX_SENTI": "100"]
    var systemNames: [String: String] = [:]
    var news: [String: [News]] = [:]
    var aliases: [String: [String]] = [:]
    var actionAliases: [String: String] = [:]
    var surfaces: [String: String] = [:]
    var words: [Word] = []
    var memory: [String] = []
    var usedWords: Set<String> = []
    var sentiment = 0
    var currentTag: Int?
    var mode = 2
    var references: [String] = Array(repeating: "", count: 9)
    var expanded: [String] = []
    var expansionDepth = 0
    var now: Date
    var seconds = 0
    var lastTalk = 0
    var visibilityCounts: [String: Int] = [:]
    var strokeArea: String?
    var strokeCount = 0
    var finalized = false
    var teachVariable: String?
    let clock: () -> Date
    let choose: (Int) -> Int

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil,
                clock: @escaping () -> Date = Date.init,
                choose: @escaping (Int) -> Int = { Int.random(in: 0 ..< $0) }) throws {
        directory = masterDirectoryURL
        stateURL = stateStoreURL ?? masterDirectoryURL.appending(path: "mae-native-state.json")
        self.clock = clock; self.choose = choose; now = clock()
        saori = DynamicSaoriRegistry(baseDirectoryURL: masterDirectoryURL)
        guard (try masterDirectoryURL.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw MaeError.invalid("Ghost directory does not exist")
        }
        for n in 1 ... 5 {
            configuration["P\(n)_SENTI_THRESHOLD"] = String([10, 30, 50, 70, 90][n - 1])
            configuration["M\(n)_SENTI_THRESHOLD"] = String([-10, -20, -40, -60, -80][n - 1])
            configuration["P\(n)_SENTI_ADJUSTMENT"] = String(n <= 2 ? 0 : -3)
            configuration["M\(n)_SENTI_ADJUSTMENT"] = String(n <= 2 ? 0 : 3)
        }
        for (slot, bounds) in [(-1, -1), (4, 7), (8, 10), (11, 16), (17, 19), (20, 22), (23, 1), (-1, -1), (-1, -1), (-1, -1)].enumerated() {
            configuration["BEGIN_SLOT\(slot)"] = String(bounds.0); configuration["END_SLOT\(slot)"] = String(bounds.1)
        }
        try loadSystemNames()
        for line in try lines("mae.ini") {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { configuration[String(pair[0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "SECUTIRY_LEVEL", with: "SECURITY_LEVEL")] = String(pair[1]).trimmingCharacters(in: .whitespaces) }
        }
        for filename in ["mae_action.txt", "mae_actions.txt"] {
            for line in try lines(filename) {
                let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { actionAliases[parts[1]] = parts[0] }
            }
        }
        for line in try lines("mae_surface.txt") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 { surfaces[parts[1]] = parts[0] }
        }
        for line in try lines("mae_alias.txt") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 { aliases[parts[0]] = Array(parts.dropFirst()) }
        }
        var common = try MaeParser(try text("mae_commonfunc.txt")); let startup = try common.program()
        guard startup.isEmpty else { throw MaeError.invalid("Common functions must use def/end") }
        vm.functions = common.functions
        try parseCorpus(try text("mae_corpus.txt", required: true))
        var partNames: [String: String] = [:]
        for line in try lines("mae_wordinfo.txt") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 { partNames[parts[0]] = parts[1] }
        }
        let excluded = Set(try lines("mae_use.txt").map { $0.trimmingCharacters(in: .whitespaces) })
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "dic" {
            for line in try lines(file.lastPathComponent) {
                guard let word = Self.capture(#"\(見出し語\s+\(([^\s()]+)"#, line),
                      let pos = Self.capture(#"\(品詞\s+\(([^)]+)"#, line) else { continue }
                let components = pos.split(whereSeparator: \.isWhitespace).map(String.init)
                if components.first.map(excluded.contains) == true { continue }
                let key = partNames[components.joined(separator: "-")] ?? components.joined(separator: "-")
                let titles = Self.capture(#"\(タイトル\s+([^)]+)"#, line)?.split(whereSeparator: \.isWhitespace).map(String.init) ?? ["一般"]
                words.append(Word(text: word, part: key, genre: Self.capture(#"\(ジャンル\s+([^\s)]+)"#, line) ?? "一般", titles: titles,
                                  mood: max(-5, min(5, Int(Self.capture(#"\(価値観\s+(-?\d+)"#, line) ?? "0") ?? 0))))
            }
        }
        vm.builtin = { [weak self] name, args, scope in
            guard let self else { throw MaeError.invalid("Session closed") }
            return try self.builtin(name, args, scope)
        }
        refreshSystem()
        for i in tags.indices where tags[i].name == "Declaration" { try vm.run(tags[i].program, vm.globals) }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
            for (name, value) in state.variables where vm.globals.cells[name] != nil {
                // Dictionary declarations define the shape; stale arrays are not imported.
                switch (vm.globals.cells[name]!.value, value) {
                case let (.array(old), .array(new)) where old.count == new.count:
                    guard !new.contains(where: { if case .array = $0 { return true }; return false }) else { throw MaeError.invalid("Invalid saved array") }
                    vm.globals.cells[name]!.value = value
                case (.array, _), (_, .array): break
                default: vm.globals.cells[name]!.value = value
                }
            }
            configuration.merge(state.configuration) { _, new in new }; news = state.news
        } else {
            try importLegacyState()
        }
        refreshSystem()
        for i in tags.indices where tags[i].name == "Initialize" { try vm.run(tags[i].program, vm.globals) }
        if configuration["USERNAME"] == "", let user = try select(["username"], fallback: false), !user.isEmpty { configuration["USERNAME"] = user }
        refreshSystem()
    }

    func text(_ name: String, required: Bool = false) throws -> String {
        let relative = name.replacingOccurrences(of: "\\", with: "/")
        guard !relative.hasPrefix("/"), !relative.contains("\0"), !relative.split(separator: "/").contains("..") else {
            throw MaeError.invalid("Invalid dictionary filename")
        }
        let path = directory.appending(path: relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            if required { throw MaeError.invalid("Missing \(name)") }; return ""
        }
        let data = try Data(contentsOf: path)
        guard data.count <= 32 * 1024 * 1024, let text = String(data: data, encoding: .utf8) ?? LegacyTextDecoder.decode(data, preferredCharset: "CP932")?.replacingOccurrences(of: "¥", with: "\\") else { throw MaeError.invalid("Cannot decode \(name)") }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
    func lines(_ name: String) throws -> [String] {
        try text(name).components(separatedBy: "\n").filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    static func capture(_ pattern: String, _ input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let range = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[range])
    }
    func parseCorpus(_ source: String) throws {
        var logical: [String] = []; var pending = ""
        for line in source.components(separatedBy: "\n") {
            if line.hasPrefix("//") { continue }
            if line.hasSuffix("\\") { pending += line.dropLast(); continue }
            logical.append(pending + line); pending = ""
        }
        if !pending.isEmpty { throw MaeError.invalid("Dangling corpus continuation") }
        var i = 0
        while i < logical.count {
            let line = logical[i]; i += 1
            guard line.hasPrefix("#") else { continue }
            let header = String(line.dropFirst())
            let parts = header.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var condition: MaeExpr?; var program: [MaeStatement] = []
            if parts.count == 2 {
                let clause = parts[1].trimmingCharacters(in: .whitespaces)
                if !clause.isEmpty {
                    guard clause.hasPrefix("case ") else { throw MaeError.invalid("Invalid tag clause: \(name)") }
                    var parser = try MaeParser(String(clause.dropFirst(5))); condition = try parser.expression()
                    guard parser.current == "<eof>" else { throw MaeError.invalid("Invalid condition: \(name)") }
                }
                var code: [String] = []
                while i < logical.count, logical[i].trimmingCharacters(in: .whitespaces) != ":end", !logical[i].hasPrefix("#") { code.append(logical[i]); i += 1 }
                guard i < logical.count, logical[i].trimmingCharacters(in: .whitespaces) == ":end" else { throw MaeError.invalid("Missing :end in \(name)") }
                i += 1; var parser = try MaeParser(code.joined(separator: "\n")); program = try parser.program()
                guard parser.current == "<eof>", parser.functions.isEmpty else { throw MaeError.invalid("Invalid tag program: \(name)") }
            }
            var sentences: [(Int, String)] = []
            while i < logical.count, !logical[i].hasPrefix("#") {
                let line = logical[i]; i += 1
                if line.isEmpty || line.hasPrefix("//") { continue }
                if let rating = Self.capture(#"^\(価値観\s+(-?\d+)\)"#, line), let end = line.firstIndex(of: ")") {
                    sentences.append((Int(rating) ?? 0, String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)))
                } else { sentences.append((0, line)) }
            }
            tags.append(Tag(name: actionAliases[name] ?? name, condition: condition, program: program, sentences: sentences))
        }
        guard !tags.isEmpty else { throw MaeError.invalid("No corpus tags") }
    }
    func refreshSystem() {
        vm.system.cells = [:]
        let cal = Calendar.current
        let components: [(String, Calendar.Component)] = [("year", .year), ("month", .month), ("day", .day), ("hour", .hour), ("minute", .minute), ("second", .second)]
        for (name, component) in components { vm.system.cells[name] = MaeCell(.integer(Int32(cal.component(component, from: now)))) }
        vm.system.cells["dayofweek"] = MaeCell(.integer(Int32(cal.component(.weekday, from: now) - 1)))
        vm.system.cells["username"] = MaeCell(.string(configuration["USERNAME"] ?? ""))
        vm.system.cells["reference"] = MaeCell(.array(references.map(MaeValue.string)))
        vm.system.cells["emotion"] = MaeCell(.integer(Int32(emotion)))
        let values = vm.system.cells
        vm.system.cells = Dictionary(uniqueKeysWithValues: values.map { (systemNames[$0.key] ?? $0.key, $0.value) })
    }
    var emotion: Int {
        var result = 0
        for level in 1 ... 5 {
            let key = "\(sentiment < 0 ? "M" : "P")\(level)_SENTI_THRESHOLD"
            let threshold = Int(configuration[key] ?? "") ?? (sentiment < 0 ? -level * 15 : level * 15)
            if sentiment < 0 ? sentiment < threshold : sentiment > threshold { result = level }
        }
        return sentiment < 0 ? -result : result
    }
    func setSentiment(_ value: Int) {
        let limit = max(0, min(1_000_000, Int(configuration["MAX_SENTI"] ?? "100") ?? 100))
        sentiment = min(limit, max(-limit, value)); refreshSystem()
    }
    func candidates(_ names: [String]) -> [String] {
        let hour = Calendar.current.component(.hour, from: now)
        let slot = (0 ... 9).first { n in
            guard let first = configuration["BEGIN_SLOT\(n)"].flatMap(Int.init), let last = configuration["END_SLOT\(n)"].flatMap(Int.init) else { return false }
            return first <= last ? (first ... last).contains(hour) : hour >= first || hour <= last
        }
        return names.flatMap { name in slot.map { [name + ".slot\($0)", name] } ?? [name] }
    }
    func select(_ names: [String], fallback: Bool = true, emit: Bool = true) throws -> String? {
        guard expansionDepth < 8 else { throw MaeError.invalid("Tag expansion depth limit") }
        expansionDepth += 1; defer { expansionDepth -= 1 }
        for name in candidates(names) + (fallback ? ["Mae.NothingToTalk", "NothingToTalk"] : []) {
            for i in tags.indices where tags[i].name == name {
                if let condition = tags[i].condition, try vm.read(condition, vm.globals).number == 0 { continue }
                let previous = currentTag; currentTag = i; mode = 2
                defer { currentTag = previous }
                try vm.run(tags[i].program, vm.globals)
                if !emit { return nil }
                let rating = emotion
                let ratings = rating == 0 ? [0] : stride(from: rating, through: 0, by: rating > 0 ? -1 : 1).map { $0 }
                for level in ratings {
                    let available = tags[i].sentences.filter { $0.0 == level }.map(\.1)
                    guard !available.isEmpty else { continue }
                    let index: Int
                    if mode == 0 {
                        if tags[i].remaining[level]?.isEmpty != false { tags[i].remaining[level] = Array(available.indices) }
                        let choice = choose(tags[i].remaining[level]!.count)
                        index = tags[i].remaining[level]!.remove(at: choice)
                    } else if mode == 1 { index = choose(available.count) }
                    else { index = (tags[i].indices[level] ?? 0) % available.count }
                    tags[i].indices[level] = (tags[i].indices[level] ?? 0) + 1
                    let output = try expand(available[index])
                    if !output.isEmpty { return output }
                }
            }
        }
        return nil
    }
    func dictionaryWord(_ key: String) throws -> String {
        let group = aliases[key] ?? [key]
        if key.hasPrefix("\\d"), let file = group.first {
            let parts = try lines(file).filter { !$0.hasPrefix("#") }
            let previous = expanded
            defer { expanded = previous }
            return try parts.isEmpty ? (configuration["UNDEFINED_WORD"] ?? "") : expand(parts[choose(parts.count)])
        }
        let byGenre = key.hasPrefix("\\j") || aliases[key] == nil
        let pool = words.filter { byGenre ? group.contains($0.genre) : group.contains($0.part) }
        guard !pool.isEmpty else { return configuration["UNDEFINED_WORD"] ?? "" }
        var choices = pool.filter { !usedWords.contains($0.text) }
        if choices.isEmpty { choices = pool }
        var preferred: [Word] = []
        let bored = memory.count == 20 && Set(memory).count == 1
        for title in memory.reversed() where !bored {
            preferred = choices.filter { $0.titles.contains(title) }; if !preferred.isEmpty { break }
        }
        if bored, let title = memory.last { preferred = choices.filter { !$0.titles.contains(title) } }
        if preferred.isEmpty { preferred = choices.filter { $0.titles.contains("一般") } }
        if preferred.isEmpty { preferred = choices }
        let word = preferred[choose(preferred.count)]; usedWords.insert(word.text)
        memory += word.titles; memory = Array(memory.suffix(20)); setSentiment(sentiment + word.mood)
        return word.text
    }
    func expand(_ input: String) throws -> String {
        guard expansionDepth < 8 else { throw MaeError.invalid("Sentence expansion depth limit") }
        expansionDepth += 1; defer { expansionDepth -= 1 }
        var output = ""; var rest = input[...]
        while let open = rest.range(of: "${") {
            output += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else { throw MaeError.invalid("Unclosed sentence variable") }
            let key = String(rest[open.upperBound ..< close]); let value: String
            if key.hasPrefix("%") { value = try executeVariable(String(key.dropFirst())) }
            else if let cell = try? vm.globals.cell(key) { value = cell.value.text }
            else { value = try dictionaryWord(key) }
            expanded.append(value); output += value
            guard output.utf8.count <= 8 * 1024 * 1024 else { throw MaeError.invalid("Sentence too large") }
            rest = rest[rest.index(after: close)...]
        }
        output += rest
        for (name, number) in surfaces { output = output.replacingOccurrences(of: "\\s[\(name)]", with: "\\s[\(number)]") }
        return output
    }
    func executeVariable(_ key: String) throws -> String {
        if let n = Int(key), n > 0, expanded.indices.contains(n - 1) { return expanded[n - 1] }
        if key.hasPrefix("info"), let n = Int(key.dropFirst(4).trimmingCharacters(in: .whitespaces)), references.indices.contains(n) { return references[n] }
        if key.hasPrefix("bin"), let n = UInt32(key.dropFirst(3).trimmingCharacters(in: .whitespaces)), n <= 255, let s = UnicodeScalar(n) { return String(s) }
        for (prefix, parameter) in [("dtalk", "TALK_INTERVAL_DETAIL"), ("talk", "TALK_INTERVAL"), ("security", "SECURITY_LEVEL"), ("secutiry", "SECURITY_LEVEL")] where key.hasPrefix(prefix) {
            guard let n = Int(key.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)), n >= 0 else { throw MaeError.invalid("Invalid \(prefix)") }
            configuration[parameter] = String(n); return ""
        }
        if key.hasPrefix("event:") { return try select([String(key.dropFirst(6))], fallback: false) ?? "" }
        if key.hasPrefix("teach:") { teachVariable = String(key.dropFirst(6)); return "\\![open,teachbox]" }
        if key.hasPrefix("saori:") {
            let parts = key.dropFirst(6).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { throw MaeError.invalid("Invalid SAORI execution variable") }
            let module = Int(parts[0]) == nil ? parts[0] : parts[1]
            let selection = Int(parts[0]) ?? Int(parts[1]) ?? -1
            guard let count = Int(parts[3]), count >= 0, let path = saoriPaths[module] else { return "" }
            let arguments = try vm.globals.cell(parts[2]).value.elements.prefix(count).map(\.text)
            let response = saori.call(path, arguments: arguments).components(separatedBy: "\u{1}")
            return response.indices.contains(selection) ? response[selection] : ""
        }
        if key == "you" { return references[0] }
        throw MaeError.invalid("Unsupported execution variable: %\(key)")
    }
    public func request(_ request: ShioriRequest, charset: String = "UTF-8") throws -> ShioriResponse {
        guard !finalized else { throw MaeError.invalid("Session closed") }
        vm.budget = 100_000; now = clock(); usedWords = []; expanded = []
        references = (0 ... 8).map { request.reference($0) ?? "" }; refreshSystem()
        let id = request.id ?? ""
        if request.headers["SecurityLevel"]?.lowercased() == "external", (Int(configuration["SECURITY_LEVEL"] ?? "8") ?? 8) >= 8 {
            return ShioriResponse(statusCode: 204, reasonPhrase: "No Content")
        }
        if id == "OnTeach", let name = teachVariable {
            try vm.write(.variable(name, nil), .string(references[0]), vm.globals); teachVariable = nil
        }
        var names = [id]
        if ["OnBoot", "OnFirstBoot", "OnKeyPress", "OnUpdateComplete", "OnUpdateFailure", "OnInstallComplete", "OnInstallFailure", "OnBIFFComplete", "OnBIFFFailure", "OnBIFF2Complete", "OnHeadlinesenseComplete", "OnHeadlinesenseFailure"].contains(id), !references[0].isEmpty { names.insert(id + "." + references[0], at: 0) }
        if id == "OnShellChanged", !references[1].isEmpty { names.insert(id + "." + references[1], at: 0) }
        if ["OnMouseDoubleClick", "OnMouseClick"].contains(id) {
            let mapped = "Mae.\(id)\(references[3] == "1" ? "Kero" : "Sakura")"
            names = (references[4].isEmpty ? [] : [mapped + "." + references[4]]) + [mapped, id]
        }
        if id == "OnSecondChange" {
            seconds += 1
            let minutes = max(0, min(1440, Int(configuration["TALK_INTERVAL"] ?? "0") ?? 0))
            let detail = max(0, min(86_400, Int(configuration["TALK_INTERVAL_DETAIL"] ?? "0") ?? 0))
            let duration = min(86_400, minutes * 60 + detail)
            let blocked = (request.headers["Status"] ?? "").split(separator: ",").contains { ["talking", "cantalk", "passive", "timecritical"].contains($0.trimmingCharacters(in: .whitespaces)) }
            if request.method == "GET", duration > 0, seconds - lastTalk >= duration, !blocked, references[3] != "0" { names.insert("Mae.Talk", at: 0); lastTalk = seconds }
        }
        names = derivedEvents(id) + names
        let value = try select(names, fallback: request.method == "GET" && !["OnSecondChange", "OnMouseMove", "OnMouseWheel"].contains(id), emit: request.method != "NOTIFY")
        if request.method == "NOTIFY" || value == nil || value == "" { return ShioriResponse(statusCode: 204, reasonPhrase: "No Content") }
        let adjustmentKey = "\(emotion < 0 ? "M" : "P")\(abs(emotion))_SENTI_ADJUSTMENT"
        setSentiment(sentiment + (Int(configuration[adjustmentKey] ?? "0") ?? 0))
        var headers = ShioriHeaders(); headers.append(name: "Charset", value: charset)
        // Never let dictionary text inject extra protocol headers.
        headers.append(name: "Value", value: value!.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "\\n"))
        return ShioriResponse(statusCode: 200, reasonPhrase: "OK", headers: headers)
    }
    public func save() throws {
        let state = State(variables: vm.globals.cells.mapValues(\.value), configuration: configuration, news: news)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }
    public func close() throws {
        if !finalized {
            vm.budget = 100_000
            for i in tags.indices where tags[i].name == "Finalize" { try vm.run(tags[i].program, vm.globals) }
            try save(); finalized = true
            for path in saoriPaths.values { saori.unload(path) }; saoriPaths = [:]
        }
    }
}
