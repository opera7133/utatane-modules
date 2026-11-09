import Foundation

struct KonokaExpression {
    indirect enum Node {
        case text(String), direct(String), unary(String, Node), binary(String, Node, Node), choose(Node, Node, Node)
    }

    private var tokens: [String] = []
    private var index = 0
    private let literal: (String) throws -> String

    init(_ source: String, literal: @escaping (String) throws -> String = { $0 }) throws {
        self.literal = literal
        let chars = Array(source)
        var cursor = 0
        while cursor < chars.count {
            if " \r\n".contains(chars[cursor]) {
                cursor += 1; continue
            }
            let start = cursor
            if chars[cursor] == "%", cursor + 1 < chars.count, chars[cursor + 1].isLetter || "_[".contains(chars[cursor + 1]) {
                cursor += 1
                while cursor < chars.count, !" \r\n".contains(chars[cursor]), !"()+-*/%=<>|&?:;".contains(chars[cursor]) {
                    cursor += 1
                }
            } else if chars[cursor] == "\"" {
                cursor += 1
                while cursor < chars.count, chars[cursor] != "\"" {
                    cursor += 1
                }
                guard cursor < chars.count else { throw KonokaError.invalidExpression(source) }
                cursor += 1
            } else if "()+-*/%=<>|&?:;".contains(chars[cursor]) {
                cursor += 1
                if cursor < chars.count, [":=", "<>", ">=", "<="].contains(String(chars[start ... cursor])) {
                    cursor += 1
                }
            } else {
                cursor += 1
                while cursor < chars.count, !" \r\n".contains(chars[cursor]), !"()+-*/%=<>|&?:;".contains(chars[cursor]) {
                    cursor += 1
                }
            }
            tokens.append(String(chars[start ..< cursor]))
            guard tokens.count <= 2048 else { throw KonokaError.limitExceeded }
        }
    }

    mutating func parse() throws -> Node {
        guard !tokens.isEmpty else { return .text("") }
        let result = try expression(0, depth: 0)
        guard index == tokens.count else { throw KonokaError.invalidExpression(tokens[index]) }
        return result
    }

    private mutating func expression(_ minimum: Int, depth: Int) throws -> Node {
        guard depth < 64, index < tokens.count else { throw KonokaError.invalidExpression("operand") }
        let token = tokens[index]; index += 1
        var lhs: Node
        if [")", ":", ";"].contains(token) {
            index -= 1; return .text("")
        }
        if ["=", "<>", ">", "<", ">=", "<=", "&", "|", ":="].contains(token) {
            index -= 1; lhs = .text("")
        } else if token == "(" {
            lhs = try expression(0, depth: depth + 1)
            guard index < tokens.count, tokens[index] == ")" else { throw KonokaError.invalidExpression(")") }
            index += 1
        } else if ["-", "+"].contains(token) {
            lhs = try .unary(token, expression(10, depth: depth + 1))
        } else if token.hasPrefix("$") {
            lhs = .direct(String(token.dropFirst()))
        } else {
            lhs = try .text(literal(token.hasPrefix("\"") ? String(token.dropFirst().dropLast()) : token))
        }
        let priorities = [";": 1, ":=": 2, "?": 3, "|": 4, "&": 5, "=": 6, "<>": 6, ">": 6, "<": 6, ">=": 6, "<=": 6, "+": 7, "-": 7, "*": 8, "/": 8, "%": 8]
        while index < tokens.count, let priority = priorities[tokens[index]], priority >= minimum {
            let op = tokens[index]; index += 1
            if op == "?" {
                let yes = try expression(0, depth: depth + 1)
                guard index < tokens.count, tokens[index] == ":" else { throw KonokaError.invalidExpression(":") }
                index += 1
                lhs = try .choose(lhs, yes, expression(priority, depth: depth + 1))
            } else {
                // Empty operands occur in the original's save/condition syntax.
                let rhs: Node = if index == tokens.count || [";", ")", ":"].contains(tokens[index]) {
                    .text("")
                } else {
                    try expression(priority + (op == ":=" ? 0 : 1), depth: depth + 1)
                }
                lhs = .binary(op, lhs, rhs)
            }
        }
        return lhs
    }

    static func evaluate(_ node: Node, read: (String) throws -> String?, write: (String, String) throws -> String) throws -> String {
        switch node {
        case let .text(value): return value
        case let .direct(key): return try read(key) ?? ""
        case let .unary(op, rhs):
            let n = try Int64(evaluate(rhs, read: read, write: write)) ?? 0
            return String(op == "-" ? 0 &- n : n)
        case let .choose(condition, yes, no):
            let condition = try evaluate(condition, read: read, write: write)
            // Original Konoka evaluates both arms, including their side effects.
            let yes = try evaluate(yes, read: read, write: write)
            let no = try evaluate(no, read: read, write: write)
            return truth(condition) ? yes : no
        case let .binary(op, a, b):
            let lhs = try evaluate(a, read: read, write: write)
            let rhs = try evaluate(b, read: read, write: write)
            if op == ":=" {
                guard lhs.hasPrefix("\\") else { return rhs }
                return try write(String(lhs.dropFirst()), rhs)
            }
            let x = Int64(lhs), y = Int64(rhs)
            switch op {
            case ";": return rhs
            case "+": return x.map { String($0 &+ (y ?? 0)) } ?? lhs + rhs
            case "-": return String((x ?? 0) &- (y ?? 0))
            case "*": return String((x ?? 0) &* (y ?? 0))
            case "/", "%":
                guard let x, let y, y != 0, !(x == .min && y == -1) else { return "#div0!" }
                return String(op == "/" ? x / y : x % y)
            case "&": return truth(lhs) && truth(rhs) ? "1" : ""
            case "|": return truth(lhs) || truth(rhs) ? "1" : ""
            case "=": return ((x != nil && y != nil) ? x == y : lhs == rhs) ? "1" : ""
            case "<>": return ((x != nil && y != nil) ? x != y : lhs != rhs) ? "1" : ""
            case ">", "<", ">=", "<=":
                let order = (x != nil && y != nil) ? (x! == y! ? 0 : x! < y! ? -1 : 1) : (lhs == rhs ? 0 : lhs < rhs ? -1 : 1)
                return (op == ">" ? order > 0 : op == "<" ? order < 0 : op == ">=" ? order >= 0 : order <= 0) ? "1" : ""
            default: throw KonokaError.invalidExpression(op)
            }
        }
    }

    static func truth(_ value: String) -> Bool {
        (Int64(value) ?? (value.isEmpty ? 0 : 1)) != 0
    }
}
