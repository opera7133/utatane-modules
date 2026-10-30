import Foundation
import ModuleProtocol

extension MaeSession {
    func builtin(_ name: String, _ args: [MaeExpr], _ scope: MaeScope) throws -> MaeValue {
        func count(_ allowed: Int...) throws {
            guard allowed.contains(args.count) else { throw MaeError.invalid("Wrong argument count: \(name)") }
        }
        func value(_ n: Int) throws -> MaeValue {
            guard args.indices.contains(n) else { throw MaeError.invalid("Missing argument: \(name)") }
            return try vm.read(args[n], scope)
        }
        func text(_ n: Int) throws -> String { try value(n).text }
        func number(_ n: Int) throws -> Int { Int(try value(n).number) }
        func put(_ n: Int, _ value: MaeValue) throws { try vm.write(args[n], value, scope) }
        func newsItem(_ headline: String, _ revision: Int) -> News? {
            let items = news[headline] ?? []
            return revision == 0 ? items.last : items.first { $0.revision == revision }
        }
        switch name {
        case "sprint":
            let parts = try args.map { try vm.read($0, scope).text }
            guard parts.reduce(0, { $0 + $1.utf8.count }) <= 8 * 1024 * 1024 else { throw MaeError.invalid("String size limit") }
            return .string(parts.joined())
        case "print": _ = try args.map { try vm.read($0, scope) }; return .integer(0)
        case "strcmp", "strncmp":
            try count(name == "strcmp" ? 2 : 3)
            var a = Array(try text(0).utf8), b = Array(try text(1).utf8)
            if name == "strncmp" { let length = max(0, try number(2)); a = Array(a.prefix(length)); b = Array(b.prefix(length)) }
            return .integer(a == b ? 0 : a.lexicographicallyPrecedes(b) ? -1 : 1)
        case "size": try count(1); return .integer(Int32(try value(0).elements.count))
        case "split":
            try count(3); let delimiter = Set(try text(1)); let source = try text(2)
            let capacity = try value(0).elements.count
            let pieces = source.split(omittingEmptySubsequences: true, whereSeparator: { delimiter.contains($0) }).prefix(capacity).map { MaeValue.string(String($0)) }
            var output = try value(0).elements
            for (i, v) in pieces.enumerated() { output[i] = v }
            if case .array = try value(0) { try put(0, .array(output)) } else { try put(0, output[0]) }
            return .integer(Int32(pieces.count))
        case "join":
            try count(3); let count = max(0, try number(0)), delimiter = try text(1)
            return .string(try value(2).elements.prefix(count).map(\.text).joined(separator: delimiter))
        case "rand":
            try count(1); let n = try number(0); guard n > 0 else { throw MaeError.invalid("rand requires a positive limit") }
            return .integer(Int32(choose(n) + 1))
        case "getini": try count(1); return .string(configuration[try text(0).replacingOccurrences(of: "SECUTIRY_LEVEL", with: "SECURITY_LEVEL")] ?? "")
        case "setini":
            try count(2); let key = try text(0).replacingOccurrences(of: "SECUTIRY_LEVEL", with: "SECURITY_LEVEL")
            guard configuration[key] != nil || key.hasPrefix("BEGIN_SLOT") || key.hasPrefix("END_SLOT") else { return .integer(-1) }
            configuration[key] = try text(1); refreshSystem(); return .integer(0)
        case "getsenti": try count(0); return .integer(Int32(sentiment))
        case "setsenti": try count(1); setSentiment(try number(0)); return .integer(Int32(sentiment))
        case "setindex":
            try count(1); let n = max(0, try number(0)); if let currentTag { tags[currentTag].indices[emotion] = n }
            return .integer(Int32(n))
        case "setrandindex": try count(1); let n = try number(0); mode = (0 ... 1).contains(n) ? n : 2; return .integer(Int32(mode))
        case "setnews":
            try count(3); let headline = try text(0), message = try text(1), mode = try number(2)
            var items = news[headline] ?? []
            if mode == 1, !items.isEmpty { items[items.count - 1].text = message; items[items.count - 1].date = now }
            else {
                guard (items.last?.revision ?? 0) < Int32.max else { throw MaeError.invalid("News revision overflow") }
                items.append(News(revision: (items.last?.revision ?? 0) + 1, text: message, date: now))
            }
            news[headline] = items; return .integer(items.last!.revision)
        case "getnews", "getnewsdate", "getnewselapsedtime":
            try count(name == "getnews" ? 3 : name == "getnewsdate" ? 8 : 5)
            let item = try newsItem(text(0), number(1))
            if name == "getnews" { try put(2, .string(item?.text ?? "")) }
            else if let item {
                let numbers: [Int]
                if name == "getnewsdate" {
                    numbers = [Calendar.Component.year, .month, .day, .hour, .minute, .second].map { Calendar.current.component($0, from: item.date) }
                } else {
                    let elapsed = max(0, min(Double(Int32.max), now.timeIntervalSince(item.date)))
                    let seconds = Int(elapsed); numbers = [seconds / 3600, seconds / 60 % 60, seconds % 60]
                }
                for (i, number) in numbers.enumerated() { try put(i + 2, .integer(Int32(number))) }
            } else {
                // The published contract clears result parameters on lookup failure.
                for index in 2 ..< args.count { try put(index, .string("")) }
            }
            return .integer(item?.revision ?? 0)
        case "deletenews":
            try count(3); let headline = try text(0), revision = try number(1), mode = try number(2)
            let old = news[headline] ?? []; var items = old
            switch mode {
            case 0: items = []
            case 1: let target = revision == 0 ? Int(old.last?.revision ?? 0) : revision; items.removeAll { $0.revision == target }
            case 2: items = Array(old.prefix(1))
            case 3: items = Array(old.suffix(1))
            default: return .integer(0)
            }
            news[headline] = items; return .integer(Int32(old.count - items.count))
        case "saoriload":
            try count(3); let module = try text(0), path = try text(2)
            guard saoriPaths[module] == nil else { return .integer(-1) }
            saori.load(path)
            guard let response = saori.response(path: path, request: "GET Version SAORI/1.0\r\nCharset: UTF-8\r\n\r\n"),
                  let message = try? ShioriMessageParser.parseResponse(response) else { try put(1, .string("")); return .integer(-1) }
            guard message.statusCode == 200 else { saori.unload(path); return .integer(Int32(message.statusCode)) }
            saoriPaths[module] = path; try put(1, .string(message.headers["Result"] ?? "")); return .integer(200)
        case "saoriunload":
            try count(1); guard let path = saoriPaths.removeValue(forKey: try text(0)) else { return .integer(-1) }
            saori.unload(path); return .integer(0)
        case "saori":
            try count(5); guard let path = saoriPaths[try text(0)] else { return .integer(-1) }
            let arguments = try value(3).elements.prefix(max(0, number(4))).map(\.text)
            let wire = (["EXECUTE SAORI/1.0", "Charset: UTF-8"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))" }).joined(separator: "\r\n") + "\r\n\r\n"
            guard let response = saori.response(path: path, request: wire), let message = try? ShioriMessageParser.parseResponse(response) else { return .integer(-1) }
            try put(1, .string(message.headers["Result"] ?? ""))
            let old = try value(2); var output = old.elements
            for i in output.indices { output[i] = .string(message.headers["Value\(i)"] ?? "") }
            if case .array = old { try put(2, .array(output)) } else { try put(2, output[0]) }
            return .integer(Int32(message.statusCode))
        default: throw MaeError.invalid("Unknown function: \(name)")
        }
    }
}
