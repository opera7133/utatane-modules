import Foundation

public enum MaeError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String { if case let .invalid(message) = self { return message }; return "mae error" }
}

indirect enum MaeValue: Codable, Equatable {
    case integer(Int32), string(String), array([MaeValue])
    var number: Int32 { switch self { case let .integer(n): n; case let .string(s): Int32(s) ?? 0; case .array: 0 } }
    var text: String { switch self { case let .integer(n): String(n); case let .string(s): s; case .array: "" } }
    var elements: [MaeValue] { if case let .array(a) = self { return a }; return [self] }
}

final class MaeCell {
    private var stored: MaeValue
    private var getter: (() -> MaeValue)?
    private var setter: ((MaeValue) -> Void)?
    var value: MaeValue {
        get { getter?() ?? stored }
        set { if let setter { setter(newValue) } else { stored = newValue } }
    }
    init(_ value: MaeValue = .integer(0)) { stored = value }
    init(get: @escaping () -> MaeValue, set: @escaping (MaeValue) -> Void) {
        stored = .integer(0); getter = get; setter = set
    }
}
final class MaeScope {
    var cells: [String: MaeCell] = [:]
    let parent: MaeScope?
    init(parent: MaeScope? = nil) { self.parent = parent }
    func cell(_ name: String) throws -> MaeCell {
        if let cell = cells[name] { return cell }
        if let parent { return try parent.cell(name) }
        throw MaeError.invalid("Undefined variable: \(name)")
    }
}
indirect enum MaeExpr {
    case value(MaeValue), variable(String, MaeExpr?), call(String, [MaeExpr])
    case unary(String, MaeExpr), binary(String, MaeExpr, MaeExpr)
}
indirect enum MaeStatement {
    case declare([(String, MaeExpr?)])
    case expression(MaeExpr), branch(MaeExpr, [MaeStatement], [MaeStatement])
    case loop(MaeExpr, [MaeStatement]), block([MaeStatement])
    case result(MaeExpr?), stop, next
}
struct MaeFunction {
    let parameters: [(String, Bool)]
    let statements: [MaeStatement]
}

/// The published mae language uses signed 32-bit arithmetic and C precedence.
struct MaeParser {
    struct Token {
        let text: String
        let value: MaeValue?
        init(_ text: String, _ value: MaeValue? = nil) { self.text = text; self.value = value }
    }
    var tokens: [Token] = []
    var position = 0
    var functions: [String: MaeFunction] = [:]
    var programDepth = 0
    init(_ source: String) throws {
        let chars = Array(source)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }; continue
            }
            if c == "\"" {
                i += 1; var value = ""; var closed = false
                while i < chars.count {
                    let c = chars[i]; i += 1
                    if c == "\"" { closed = true; break }
                    if c == "\\" {
                        guard i < chars.count else { throw MaeError.invalid("Unterminated string") }
                        let escaped = chars[i]; i += 1
                        switch escaped {
                        case "n": value += "\n"
                        case "t": value += "\t"
                        case "\\", "\"": value.append(escaped)
                        case "x":
                            var digits = ""
                            while i < chars.count, chars[i].isASCII, chars[i].isNumber { digits.append(chars[i]); i += 1 }
                            guard let n = UInt32(digits), let scalar = UnicodeScalar(n) else { throw MaeError.invalid("Invalid character escape") }
                            value.unicodeScalars.append(scalar)
                        default: throw MaeError.invalid("Unknown string escape: \(escaped)")
                        }
                    } else { value.append(c) }
                }
                guard closed else { throw MaeError.invalid("Unterminated string") }
                tokens.append(Token("string", .string(value))); continue
            }
            if c.isASCII, c.isNumber {
                var digits = ""
                while i < chars.count, chars[i].isASCII, chars[i].isNumber { digits.append(chars[i]); i += 1 }
                guard let n = Int64(digits), n <= Int64(UInt32.max) else { throw MaeError.invalid("Integer out of range") }
                tokens.append(Token(digits, .integer(Int32(truncatingIfNeeded: n)))); continue
            }
            if c.isASCII, c.isLetter || c == "_" {
                var name = ""
                while i < chars.count, chars[i].isASCII, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    name.append(chars[i]); i += 1
                }
                tokens.append(Token(name)); continue
            }
            let pair = i + 1 < chars.count ? String(chars[i ... i + 1]) : ""
            if ["==", "!=", "<=", ">=", "&&", "||"].contains(pair) { tokens.append(Token(pair)); i += 2 }
            else if "()[],;+-*/%<>=!&".contains(c) { tokens.append(Token(String(c))); i += 1 }
            else { throw MaeError.invalid("Unexpected program character: \(c)") }
        }
        tokens.append(Token("<eof>"))
    }
    var current: String { tokens[position].text }
    mutating func take(_ text: String) -> Bool { if current == text { position += 1; return true }; return false }
    mutating func expect(_ text: String) throws { guard take(text) else { throw MaeError.invalid("Expected \(text), got \(current)") } }
    mutating func identifier() throws -> String {
        let name = current
        guard name.first?.isASCII == true, name.first?.isLetter == true || name.first == "_",
              tokens[position].value == nil else { throw MaeError.invalid("Expected identifier, got \(name)") }
        position += 1; return name
    }
    mutating func program(until stops: Set<String> = ["<eof>"]) throws -> [MaeStatement] {
        guard programDepth < 128 else { throw MaeError.invalid("Program nesting limit") }
        programDepth += 1; defer { programDepth -= 1 }
        var result: [MaeStatement] = []
        while !stops.contains(current), current != "<eof>" {
            if take(";") { continue }
            if take("def") {
                let name = try identifier(); try expect("("); var params: [(String, Bool)] = []
                if !take(")") {
                    repeat { let name = try identifier(); params.append((name, take("&"))) } while take(",")
                    try expect(")")
                }
                let body = try program(until: ["end"]); try expect("end")
                guard functions[name] == nil else { throw MaeError.invalid("Duplicate function: \(name)") }
                functions[name] = MaeFunction(parameters: params, statements: body)
            } else if current == "print", position + 1 < tokens.count, tokens[position + 1].text != "(" {
                position += 1; var args: [MaeExpr] = []
                repeat { args.append(try expression()) } while take(",")
                try expect(";"); result.append(.expression(.call("print", args)))
            } else if take("var") {
                var vars: [(String, MaeExpr?)] = []
                repeat {
                    let name = try identifier(); var size: MaeExpr?
                    if take("[") { size = try expression(); try expect("]") }
                    vars.append((name, size))
                } while take(",")
                try expect(";"); result.append(.declare(vars))
            } else if take("if") {
                let condition = try expression(); try expect("then")
                let yes = try program(until: ["end", "else"])
                var no: [MaeStatement] = []
                if take("end") { if take("else") { no = try program(until: ["end"]); try expect("end") } }
                else { try expect("else"); no = try program(until: ["end"]); try expect("end") }
                result.append(.branch(condition, yes, no))
            } else if take("while") {
                let condition = try expression(); try expect("do")
                let body = try program(until: ["end"]); try expect("end"); result.append(.loop(condition, body))
            } else if take("begin") {
                let body = try program(until: ["end"]); try expect("end"); result.append(.block(body))
            } else if take("return") {
                let value: MaeExpr? = current == ";" ? nil : try expression()
                try expect(";"); result.append(.result(value))
            } else if take("break") { try expect(";"); result.append(.stop) }
            else if take("continue") { try expect(";"); result.append(.next) }
            else { result.append(.expression(try expression())); try expect(";") }
        }
        return result
    }
    mutating func expression(_ minimum: Int = 1, depth: Int = 0) throws -> MaeExpr {
        guard depth < 128 else { throw MaeError.invalid("Expression nesting limit") }
        var lhs: MaeExpr
        if ["-", "+", "!"].contains(current) {
            let op = current; position += 1; lhs = .unary(op, try expression(8, depth: depth + 1))
        } else if take("(") { lhs = try expression(depth: depth + 1); try expect(")") }
        else if let value = tokens[position].value { lhs = .value(value); position += 1 }
        else {
            let name = try identifier()
            if take("(") {
                var args: [MaeExpr] = []
                if !take(")") { repeat { args.append(try expression(depth: depth + 1)) } while take(","); try expect(")") }
                lhs = .call(name, args)
            } else {
                var index: MaeExpr?
                if take("[") { index = try expression(depth: depth + 1); try expect("]") }
                lhs = .variable(name, index)
            }
        }
        let precedence = ["=": 1, "||": 2, "&&": 3, "==": 4, "!=": 4, "<": 4, ">": 4, "<=": 4, ">=": 4,
                          "+": 5, "-": 5, "*": 6, "/": 6, "%": 6]
        while let level = precedence[current], level >= minimum {
            let op = current; position += 1
            let rhs = try expression(op == "=" ? level : level + 1, depth: depth + 1)
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }
}

/// A bounded interpreter: limits fail the request instead of hanging the SHIORI host.
final class MaeInterpreter {
    enum Flow: Error { case result(MaeValue), stop, next }
    let system = MaeScope()
    lazy var globals = MaeScope(parent: system)
    var functions: [String: MaeFunction] = [:]
    var builtin: ((String, [MaeExpr], MaeScope) throws -> MaeValue)?
    var budget = 100_000
    var depth = 0
    func tick() throws { budget -= 1; guard budget >= 0 else { throw MaeError.invalid("Program instruction limit") } }
    func read(_ expression: MaeExpr, _ scope: MaeScope) throws -> MaeValue {
        try tick()
        switch expression {
        case let .value(v): return v
        case let .variable(name, index):
            let value = try scope.cell(name).value
            guard let index else { return value }
            let n = Int(try read(index, scope).number)
            guard case let .array(items) = value, items.indices.contains(n) else { throw MaeError.invalid("Array index out of range: \(name)") }
            return items[n]
        case let .call(name, args):
            guard depth < 64 else { throw MaeError.invalid("Function recursion limit") }
            depth += 1; defer { depth -= 1 }
            if let function = functions[name] {
                guard args.count == function.parameters.count else { throw MaeError.invalid("Wrong argument count: \(name)") }
                let local = MaeScope(parent: system)
                for (parameter, argument) in zip(function.parameters, args) {
                    if parameter.1 {
                        local.cells[parameter.0] = try reference(argument, scope)
                    } else { local.cells[parameter.0] = MaeCell(try read(argument, scope)) }
                }
                do { try run(function.statements, local) } catch let Flow.result(v) { return v }
                return .integer(0)
            }
            guard let builtin else { throw MaeError.invalid("Unknown function: \(name)") }
            return try builtin(name, args, scope)
        case let .unary(op, value):
            let number = try read(value, scope).number
            return .integer(op == "!" ? (number == 0 ? 1 : 0) : op == "-" ? 0 &- number : number)
        case let .binary(op, a, b):
            if op == "=" { let value = try read(b, scope); try write(a, value, scope); return value }
            let x = try read(a, scope).number
            if op == "&&", x == 0 { return .integer(0) }
            if op == "||", x != 0 { return .integer(1) }
            let y = try read(b, scope).number
            switch op {
            case "+": return .integer(x &+ y)
            case "-": return .integer(x &- y)
            case "*": return .integer(x &* y)
            case "/", "%":
                guard y != 0 else { throw MaeError.invalid("Division by zero") }
                let quotient = Int64(x) / Int64(y), remainder = Int64(x) % Int64(y)
                return .integer(Int32(truncatingIfNeeded: op == "/" ? quotient : remainder))
            case "==": return .integer(x == y ? 1 : 0)
            case "!=": return .integer(x != y ? 1 : 0)
            case "<": return .integer(x < y ? 1 : 0)
            case ">": return .integer(x > y ? 1 : 0)
            case "<=": return .integer(x <= y ? 1 : 0)
            case ">=": return .integer(x >= y ? 1 : 0)
            case "&&": return .integer(y != 0 ? 1 : 0)
            case "||": return .integer(y != 0 ? 1 : 0)
            default: throw MaeError.invalid("Unknown operator: \(op)")
            }
        }
    }
    func reference(_ expression: MaeExpr, _ scope: MaeScope) throws -> MaeCell {
        guard case let .variable(name, index) = expression else { throw MaeError.invalid("Reference argument requires a variable") }
        let cell = try scope.cell(name)
        guard let index else { return cell }
        let n = Int(try read(index, scope).number)
        guard case let .array(items) = cell.value, items.indices.contains(n) else { throw MaeError.invalid("Array index out of range") }
        return MaeCell(get: { cell.value.elements[n] }, set: { value in
            var items = cell.value.elements; items[n] = value; cell.value = .array(items)
        })
    }
    func write(_ expression: MaeExpr, _ value: MaeValue, _ scope: MaeScope) throws {
        guard case let .variable(name, index) = expression else { throw MaeError.invalid("Assignment requires a variable") }
        let cell = try scope.cell(name)
        if let index {
            let n = Int(try read(index, scope).number)
            guard case var .array(items) = cell.value, items.indices.contains(n) else { throw MaeError.invalid("Array index out of range: \(name)") }
            if case .array = value { throw MaeError.invalid("Nested arrays are not supported") }
            items[n] = value; cell.value = .array(items)
        } else {
            switch (cell.value, value) {
            case let (.array(old), .array(new)) where old.count == new.count: cell.value = value
            case (.array, _), (_, .array): throw MaeError.invalid("Cannot change variable array shape")
            default: cell.value = value
            }
        }
    }
    func run(_ statements: [MaeStatement], _ scope: MaeScope) throws {
        for statement in statements {
            try tick()
            switch statement {
            case let .declare(variables):
                for (name, count) in variables {
                    guard scope.cells[name] == nil else { throw MaeError.invalid("Duplicate variable: \(name)") }
                    if let count {
                        let n = Int(try read(count, scope).number)
                        guard (1 ... 100_000).contains(n) else { throw MaeError.invalid("Invalid array size") }
                        scope.cells[name] = MaeCell(.array(Array(repeating: .integer(0), count: n)))
                    } else { scope.cells[name] = MaeCell() }
                }
            case let .expression(e): _ = try read(e, scope)
            case let .branch(c, yes, no): try run(read(c, scope).number != 0 ? yes : no, scope)
            case let .loop(condition, body):
                while try read(condition, scope).number != 0 {
                    do { try run(body, scope) } catch Flow.stop { break } catch Flow.next { continue }
                }
            case let .block(body): try run(body, MaeScope(parent: system))
            case let .result(value): throw Flow.result(try value.map { try read($0, scope) } ?? .integer(0))
            case .stop: throw Flow.stop
            case .next: throw Flow.next
            }
        }
    }
}
