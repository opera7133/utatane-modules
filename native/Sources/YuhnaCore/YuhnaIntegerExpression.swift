import Foundation

/// Integer expressions in the assignment records of YDF/1.07 dictionaries.
struct YuhnaIntegerExpression {
    private var remaining: Substring
    private var operationCount = 0
    private let lookup: (String) -> String?
    private var hasArithmetic = false

    init(_ source: String, lookup: @escaping (String) -> String?) {
        remaining = source[...]
        self.lookup = lookup
    }

    mutating func evaluate() -> Int64? {
        guard let result = sum(depth: 0), hasArithmetic else { return nil }
        skipSpaces()
        return remaining.isEmpty ? result : nil
    }

    private mutating func sum(depth: Int) -> Int64? {
        guard var result = product(depth: depth) else { return nil }
        while let operation = takeOperator(in: "+-") {
            guard let rhs = product(depth: depth) else { return nil }
            let value = operation == "+" ? result.addingReportingOverflow(rhs) : result.subtractingReportingOverflow(rhs)
            guard !value.overflow else { return nil }
            result = value.partialValue
        }
        return result
    }

    private mutating func product(depth: Int) -> Int64? {
        guard var result = term(depth: depth) else { return nil }
        while let operation = takeOperator(in: "*/") {
            guard let rhs = term(depth: depth) else { return nil }
            if operation == "*" {
                let value = result.multipliedReportingOverflow(by: rhs)
                guard !value.overflow else { return nil }
                result = value.partialValue
            } else {
                guard !(result == .min && rhs == -1) else { return nil }
                result = rhs == 0 ? 0 : result / rhs
            }
        }
        return result
    }

    private mutating func term(depth: Int) -> Int64? {
        guard depth < 32, operationCount < 1024 else { return nil }
        operationCount += 1
        skipSpaces()
        if remaining.first == "(" {
            remaining.removeFirst()
            guard let result = sum(depth: depth + 1) else { return nil }
            skipSpaces()
            guard remaining.first == ")" else { return nil }
            remaining.removeFirst()
            return result
        }
        let start = remaining
        if remaining.first == "-" || remaining.first == "+" {
            remaining.removeFirst()
        }
        let atom = remaining.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "%") }
        guard !atom.isEmpty else { return nil }
        remaining.removeFirst(atom.count)
        let token = String(start[..<remaining.startIndex])
        if let value = Int64(token) {
            return value
        }
        if let value = lookup(token) {
            return Int64(value) ?? 0
        }
        guard !token.first!.isNumber, !token.contains("%") else { return nil }
        return 0
    }

    private mutating func takeOperator(in operators: String) -> Character? {
        skipSpaces()
        guard let next = remaining.first, operators.contains(next) else { return nil }
        hasArithmetic = true
        remaining.removeFirst()
        return next
    }

    private mutating func skipSpaces() {
        remaining = remaining.drop(while: \.isWhitespace)
    }
}
