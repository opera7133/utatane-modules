import Foundation
import LegacyText

struct KonokaDictionary {
    struct Event { let id: String; let condition: String; let script: String }
    struct Macro { let name: String; let value: String }
    var words: [(String, [String])] = []
    var events: [Event] = []
    var resources: [String: [String]] = [:]
    var responses: [(String, String)] = []
    private var macros: [Macro] = []
    private var serial = 0

    static func load(_ directory: URL) throws -> Self {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var configs = ["konoka.ini"]
        if let data = try? Data(contentsOf: root.appending(path: "descript.txt")), let text = LegacyTextDecoder.decode(data) {
            for line in text.components(separatedBy: .newlines) where line.lowercased().hasPrefix("shiori,") {
                let filename = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
                let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                if !stem.isEmpty {
                    configs.append((filename as NSString).deletingPathExtension + ".ini")
                }
            }
        }
        configs.append("ks_cfg.txt")
        guard let config = configs.map({ root.appending(path: $0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw KonokaError.invalidDictionary("konoka.ini")
        }
        func contents(_ url: URL) throws -> Data {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/"),
                  let size = try resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024
            else {
                throw KonokaError.invalidDictionary(url.lastPathComponent)
            }
            return try Data(contentsOf: resolved)
        }
        guard let configText = try LegacyTextDecoder.decode(contents(config)) else { throw KonokaError.invalidDictionary("config charset") }
        var dictionary = Self(), total = 0, loaded = 0
        var encryptedOutputs: [(URL, Data)] = []
        for raw in configText.components(separatedBy: .newlines) {
            let options = raw.components(separatedBy: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            let name = raw.split(separator: ",", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if name.isEmpty || name.hasPrefix("#") || name.hasPrefix("//") {
                continue
            }
            let path = name.replacingOccurrences(of: "\\", with: "/")
            guard !path.hasPrefix("/"), !path.contains(":"), !path.split(separator: "/").contains("..") else {
                throw KonokaError.invalidDictionary("dictionary path")
            }
            var urls: [URL]
            if path.contains("*") || path.contains("?") {
                let pattern = "^" + NSRegularExpression.escapedPattern(for: path).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
                let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
                urls = (all?.allObjects as? [URL] ?? []).filter { String($0.path.dropFirst(root.path.count + 1)).range(of: pattern, options: .regularExpression) != nil }.sorted { $0.path < $1.path }
            } else {
                let url = root.appending(path: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    urls = [url]
                } else {
                    let base = url.deletingPathExtension()
                    urls = ["xdc", "xdi"].map { base.appendingPathExtension($0) }.first { FileManager.default.fileExists(atPath: $0.path) }.map { [$0] } ?? []
                }
            }
            guard !urls.isEmpty else { throw KonokaError.invalidDictionary(path) }
            for url in urls {
                var data = try contents(url)
                if url.pathExtension.lowercased() == "txt", options.contains("e") {
                    let output = url.deletingPathExtension().appendingPathExtension("xdc")
                    guard output.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path + "/") else { throw KonokaError.invalidDictionary("encrypted output path") }
                    try encryptedOutputs.append((output, KonokaCipher.encode(data, format: .xdc)))
                }
                if url.pathExtension.lowercased() == "xdi" {
                    data = try KonokaCipher.decode(data)
                }
                if url.pathExtension.lowercased() == "xdc" {
                    data = try KonokaCipher.decode(data, format: .xdc)
                }
                total += data.count; loaded += 1
                guard total <= 8 * 1024 * 1024, loaded <= 1024 else { throw KonokaError.limitExceeded }
                guard !data.contains(0), let source = String(data: data, encoding: .utf8) ?? LegacyTextDecoder.decode(data, preferredCharset: "Shift_JIS") else {
                    throw KonokaError.invalidDictionary("charset")
                }
                try dictionary.parse(source.replacingOccurrences(of: "¥", with: "\\"))
            }
        }
        guard loaded > 0 else { throw KonokaError.invalidDictionary("no dictionaries") }
        for (url, data) in encryptedOutputs {
            try data.write(to: url, options: .atomic)
        }
        return dictionary
    }

    mutating func parse(_ source: String) throws {
        var pending: String?
        var inComment = false
        func isHeader(_ s: String) -> Bool {
            s.hasPrefix("@") || s.hasPrefix("*") || s.hasPrefix("\\") || s.hasPrefix("$") || s.hasPrefix("Option,")
        }
        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            while let begin = line.range(of: inComment ? "*/" : "/*") {
                if inComment {
                    line = String(line[begin.upperBound...]); inComment = false
                } else if let end = line.range(of: "*/", range: begin.upperBound ..< line.endIndex) {
                    line.removeSubrange(begin.lowerBound ..< end.upperBound)
                } else {
                    line = String(line[..<begin.lowerBound]); inComment = true
                }
            }
            if inComment {
                continue
            }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") {
                if let value = pending {
                    try register(value); pending = nil
                }
                continue
            }
            for macro in macros {
                line = try apply(macro, to: line)
                guard line.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            }
            if pending != nil {
                guard pending!.utf8.count + line.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
                pending! += line; continue
            }
            guard line.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            if isHeader(line), firstComma(line) == nil, !line.hasPrefix("$") {
                pending = line.hasSuffix("&") ? line : line + ","
            } else if let comma = firstComma(line) {
                let key = String(line[..<comma])
                let value = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                if value.isEmpty {
                    pending = line
                } else if ["\\id", "\\ev"].contains(key), firstComma(value) == nil {
                    pending = line + ","
                } else {
                    try register(line)
                }
            } else {
                try register(line)
            }
        }
        if let pending {
            try register(pending)
        }
    }

    private func firstComma(_ line: String) -> String.Index? {
        var escaped = false
        for i in line.indices {
            if line[i] == ",", !escaped {
                return i
            }
            if line[i] == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
        }
        return nil
    }

    private mutating func register(_ source: String) throws {
        guard let comma = firstComma(source) else { return }
        let key = String(source[..<comma]).trimmingCharacters(in: .whitespaces)
        let value = String(source[source.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("$") {
            macros.append(.init(name: String(key.dropFirst()), value: value)); return
        }
        if key == "Option" {
            return
        }
        if key.hasPrefix("@") {
            addEvent(String(key.dropFirst()), value); return
        }
        if key == "\\ev", let next = firstComma(value) {
            addEvent(String(value[..<next]), String(value[value.index(after: next)...]).trimmingCharacters(in: .whitespaces)); return
        }
        if key.hasPrefix("*") {
            resources[String(key.dropFirst()), default: []].append(value.replacingOccurrences(of: "\\[1]", with: "\u{1}").replacingOccurrences(of: "\\[2]", with: "\u{2}")); return
        }
        if key == "\\id", let next = firstComma(value) {
            resources[String(value[..<next]).trimmingCharacters(in: .whitespaces), default: []].append(String(value[value.index(after: next)...]).replacingOccurrences(of: "\\[1]", with: "\u{1}").replacingOccurrences(of: "\\[2]", with: "\u{2}")); return
        }
        if ["\\re", "\\hl"].contains(key), let next = firstComma(value) {
            responses.append((String(value[..<next]).trimmingCharacters(in: .whitespaces), String(value[value.index(after: next)...]))); return
        }
        guard key.hasPrefix("\\") else { return }
        // Escaped commas are literal dictionary data.
        let marker = "\u{0}"
        let values = value.replacingOccurrences(of: "\\,", with: marker).components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: marker, with: ",")
        }
        let name = String(key.dropFirst())
        if let index = words.firstIndex(where: { $0.0 == name }) {
            words[index].1 += values
        } else {
            words.append((name, values))
        }
    }

    private mutating func addEvent(_ source: String, _ script: String) {
        let fields = source.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false)
        events.append(.init(id: String(fields[0]).trimmingCharacters(in: .whitespaces), condition: fields.count == 2 ? String(fields[1]).trimmingCharacters(in: .whitespaces) : "", script: script))
    }

    private mutating func apply(_ macro: Macro, to source: String) throws -> String {
        guard !macro.name.isEmpty else { throw KonokaError.invalidDictionary("empty macro") }
        var literals = [""], parameters: [Int] = []
        let characters = Array(macro.name)
        var cursor = 0
        while cursor < characters.count {
            if characters[cursor] == "%", cursor + 1 < characters.count,
               let digit = characters[cursor + 1].wholeNumberValue, digit < 10
            {
                parameters.append(digit); literals.append(""); cursor += 2
            } else {
                literals[literals.count - 1].append(characters[cursor]); cursor += 1
            }
        }
        guard parameters.count <= 10, !literals[0].isEmpty else { throw KonokaError.invalidDictionary("macro prefix") }
        var output = "", search = source.startIndex, copied = source.startIndex
        while search < source.endIndex, let prefix = source.range(of: literals[0], range: search ..< source.endIndex) {
            var end = prefix.upperBound, captures: [String] = [], matched = true
            for literal in literals.dropFirst() {
                if literal.isEmpty {
                    captures.append(""); continue
                }
                guard let next = source.range(of: literal, range: end ..< source.endIndex) else { matched = false; break }
                captures.append(String(source[end ..< next.lowerBound])); end = next.upperBound
            }
            guard matched else { search = prefix.upperBound; continue }
            var replacement = macro.value
            for (digit, capture) in zip(parameters, captures) {
                replacement = replacement.replacingOccurrences(of: "%\(digit)", with: capture)
            }
            replacement = replacement.replacingOccurrences(of: "$N", with: String(serial)); serial += 1
            output += source[copied ..< prefix.lowerBound]; output += replacement
            guard output.utf8.count <= 1024 * 1024 else { throw KonokaError.limitExceeded }
            copied = end; search = end
        }
        output += source[copied...]
        return output
    }
}
