import Foundation

/// Shared lexer for 0.3/0.4 lists, conditions, and PSY argument lists.
enum HitomiSyntax {
    static func split(_ source: String, on separators: Set<Character>, whitespace: Bool = false) throws -> [String] {
        var result: [String] = [], buffer = "", depth = 0, quoted = false, escaped = false
        for c in source {
            if c == "\"", !escaped {
                quoted.toggle()
            }
            if !quoted {
                if c == "{" {
                    depth += 1
                }
                if c == "}" {
                    depth -= 1
                }
                guard (0 ... 32).contains(depth) else { throw HitomiError.invalidDictionary("braces") }
            }
            if !quoted, depth == 0, separators.contains(c) || (whitespace && c.isWhitespace) {
                if !whitespace || !buffer.isEmpty {
                    result.append(buffer.trimmingCharacters(in: .whitespaces))
                }
                buffer = ""
            } else {
                buffer.append(c)
            }
            if c == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
        }
        guard depth == 0, !quoted else { throw HitomiError.invalidDictionary("unterminated list/string") }
        if !whitespace || !buffer.isEmpty {
            result.append(buffer.trimmingCharacters(in: .whitespaces))
        }
        return result
    }

    static func literal(_ source: String) -> String? {
        guard source.hasPrefix("\""), source.hasSuffix("\""), source.count >= 2 else { return nil }
        return String(source.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    static func body(_ source: String) -> String? {
        source.hasPrefix("${") && source.hasSuffix("}") ? String(source.dropFirst(2).dropLast()) : nil
    }

    static func callEnd(_ source: String, from start: String.Index) throws -> String.Index {
        var depth = 0, quoted = false, escaped = false
        for i in source[start...].indices {
            let c = source[i]
            if c == "\"", !escaped {
                quoted.toggle()
            }
            if !quoted {
                if c == "{" {
                    depth += 1
                }
                if c == "}" {
                    depth -= 1; if depth == 0 {
                        return i
                    }
                }
                guard depth <= 32 else { throw HitomiError.limitExceeded }
            }
            if c == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
        }
        throw HitomiError.invalidDictionary("unterminated command")
    }
}

struct HitomiEntry {
    var values: [String]
    var conditions: [String] = []
    var keyword: String?
    var isDefault = false
}

struct HitomiPreprocessor {
    var definitions = Set<String>()
    private var stack: [(parent: Bool, test: Bool, hadElse: Bool)] = []
    var active: Bool {
        stack.last.map { $0.parent && $0.test } ?? true
    }

    mutating func consume(_ source: String) throws -> Bool {
        let parts = source.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard let directive = parts.first, directive.hasPrefix("#") else { return false }
        let label = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch directive {
        case "#define": if active {
                definitions.insert(label)
            }
        case "#undef": if active {
                definitions.remove(label)
            }
        case "#if0", "#if1", "#ifdef", "#ifndef":
            guard stack.count < 32 else { throw HitomiError.limitExceeded }
            let test = directive == "#if1" || (directive == "#ifdef" && definitions.contains(label)) || (directive == "#ifndef" && !definitions.contains(label))
            stack.append((active, test, false))
        case "#else":
            guard var last = stack.popLast(), !last.hadElse else { throw HitomiError.invalidDictionary("#else") }
            last.test.toggle(); last.hadElse = true; stack.append(last)
        case "#endif": guard stack.popLast() != nil else { throw HitomiError.invalidDictionary("#endif") }
        case "#include": throw HitomiError.unsupportedSyntax("#include")
        default: break // Ordinary comments.
        }
        return true
    }

    func finishFile() throws {
        guard stack.isEmpty else { throw HitomiError.invalidDictionary("missing #endif") }
    }
}
