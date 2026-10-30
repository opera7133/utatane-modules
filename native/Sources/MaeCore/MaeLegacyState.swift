import Foundation

extension MaeSession {
    // The original writer escapes commas, quotes, backslashes and line feeds
    // inside quoted fields. This is not RFC 4180 CSV (quotes are backslash escaped).
    static func legacyFields(_ line: String) throws -> [String] {
        var fields: [String] = [], field = "", quoted = false, escaped = false
        for character in line {
            if escaped {
                switch character {
                case "n": field.append("\n")
                case "r": field.append("\r")
                case "\\", "\"", ",": field.append(character)
                default: field.append("\\"); field.append(character)
                }
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "\"" { quoted.toggle() }
            else if character == ",", !quoted { fields.append(field); field = "" }
            else { field.append(character) }
        }
        guard !quoted, !escaped else { throw MaeError.invalid("Malformed original mae save record") }
        fields.append(field); return fields
    }

    func importLegacyState() throws {
        for line in try lines("mae_variable.txt") {
            let fields = try Self.legacyFields(line)
            guard fields.count == 6, let shape = Int(fields[1]), [1, 2].contains(shape),
                  let index = Int(fields[2]), index >= 0,
                  let type = Int(fields[3]), [0, 1, 3].contains(type),
                  let integer = Int32(fields[4]) else { throw MaeError.invalid("Invalid original mae variable record") }
            // Ignore removed declarations and array elements beyond the current
            // declaration, without allocating from untrusted save dimensions.
            guard let cell = vm.globals.cells[fields[0]] else { continue }
            let value: MaeValue = type == 0 ? .integer(integer) : .string(fields[5])
            if shape == 2, case var .array(array) = cell.value, array.indices.contains(index) {
                array[index] = value; cell.value = .array(array)
            } else if shape == 1, index == 0 {
                if case .array = cell.value { continue }
                cell.value = value
            }
        }
        for line in try lines("mae_news.txt") {
            let fields = try Self.legacyFields(line)
            guard fields.count == 5, let revision = Int32(fields[1]), revision > 0,
                  let low = UInt32(fields[2]), let high = UInt32(fields[3]) else { throw MaeError.invalid("Invalid original mae News record") }
            let ticks = UInt64(high) << 32 | UInt64(low)
            // Original mae stores local wall-clock fields as FILETIME, without
            // converting them to UTC. Interpreting it as a UTC instant shifts
            // Japanese saves by nine hours (confirmed against the original DLL).
            let encoded = Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: encoded)
            guard let date = Calendar.current.date(from: components) else { throw MaeError.invalid("Invalid original mae News date") }
            guard !(news[fields[0]] ?? []).contains(where: { $0.revision == revision }) else { throw MaeError.invalid("Duplicate original mae News revision") }
            news[fields[0], default: []].append(News(revision: revision, text: fields[4], date: date))
        }
        for key in Array(news.keys) { news[key]!.sort { $0.revision < $1.revision } }
    }

    func loadSystemNames() throws {
        let source = try text("mae_systemvar.txt")
        guard !source.isEmpty else { return }
        let declarations = source.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("var ") }
        let canonical = ["year", "month", "day", "hour", "minute", "second", "dayofweek", "username", "emotion", "reference"]
        guard declarations.count == canonical.count else { throw MaeError.invalid("Invalid system variable declarations") }
        var seen = Set<String>()
        for (index, declaration) in declarations.enumerated() {
            guard let name = Self.capture(#"^\s*var\s+([A-Za-z_][A-Za-z_0-9]*)\s*(?:\[\s*8\s*\])?\s*;\s*$"#, declaration),
                  seen.insert(name).inserted else { throw MaeError.invalid("Invalid system variable name") }
            systemNames[canonical[index]] = name
        }
    }
}
