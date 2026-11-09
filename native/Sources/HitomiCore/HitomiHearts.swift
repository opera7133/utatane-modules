import Foundation

/// Importable PSY memory. Native changes are saved separately from the source files.
struct HitomiHearts: Codable, Equatable {
    struct Word: Codable, Equatable {
        var kind: String
        var score: Int
        var relations: [String: Int] = [:]
        var mass: [String: Double] = [:]
        enum CodingKeys: CodingKey { case kind, score, relations }
    }

    var words: [String: Word] = [:]
    var order: [String] = []

    mutating func load(_ source: String) throws {
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { throw HitomiError.invalidDictionary("Hearts record") }
            let kind = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard ["Myself", "Master", "Friends", "Friend", "Word", "Words", "Short", "Dead"].contains(kind) else { throw HitomiError.invalidDictionary("Hearts kind") }
            let fields = line[line.index(after: colon)...].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty, let score = Int(fields[1]), (-1000 ... 1000).contains(score), fields.count % 2 == 0 else { throw HitomiError.invalidDictionary("Hearts fields") }
            if kind == "Dead" {
                continue
            }
            var record = Word(kind: kind == "Words" ? "Word" : kind == "Friend" ? "Friends" : kind, score: score)
            for i in stride(from: 2, to: fields.count, by: 2) {
                guard let strength = Int(fields[i + 1]), (1 ... 1000).contains(strength), !fields[i].isEmpty else { throw HitomiError.invalidDictionary("Hearts relation") }
                record.relations[fields[i]] = strength
            }
            if words[fields[0]] == nil {
                order.append(fields[0])
            }
            words[fields[0]] = record
            guard words.count <= 16384 else { throw HitomiError.limitExceeded }
        }
    }

    func matches(_ name: String, filter: String) -> Bool {
        guard let word = words[name] else { return false }
        switch filter {
        case "Words": return ["Word", "Short"].contains(word.kind)
        case "Friends": return word.kind == "Friends"
        default: return true
        }
    }

    mutating func append(_ names: [String], friends: Bool = false) throws -> [String] {
        var added: [String] = []
        for name in names where !name.isEmpty {
            guard name.utf8.count <= 4096, words.count < 16384 else { throw HitomiError.limitExceeded }
            if words[name] == nil {
                words[name] = .init(kind: friends ? "Friends" : "Short", score: 0); order.append(name)
            }
            if !["Myself", "Master"].contains(words[name]!.kind) {
                added.append(name)
            }
        }
        return added
    }

    mutating func preference(_ names: [String], score: Int) throws {
        for name in names where !name.isEmpty {
            if words[name] == nil {
                guard words.count < 16384 else { throw HitomiError.limitExceeded }
                words[name] = .init(kind: "Word", score: score); order.append(name)
            } else if words[name]?.kind != "Short" {
                words[name]?.score = score
            }
        }
    }

    mutating func relate(_ first: String, _ second: String) throws {
        guard first != second, words[first] != nil, words[second] != nil else { return }
        for (owner, target) in [(first, second), (second, first)] where words[target]?.kind != "Short" {
            var record = words[owner]!
            if record.mass.isEmpty {
                record.mass = record.relations.mapValues { Double($0) / 1000 }
            }
            record.mass[target, default: 0] += 1
            guard record.mass.count <= 16384 else { throw HitomiError.limitExceeded }
            let sum = record.mass.values.reduce(0, +)
            let keys = record.mass.keys.sorted()
            var remaining = 1000
            record.relations.removeAll(keepingCapacity: true)
            for (index, key) in keys.enumerated() {
                let strength = index == keys.count - 1 ? remaining : Int((record.mass[key]! / sum * 1000).rounded(.down))
                if strength > 0 {
                    record.relations[key] = strength
                }
                remaining -= strength
            }
            words[owner] = record
        }
    }

    mutating func study(_ name: String, related: [String]) throws {
        guard !name.isEmpty, name.utf8.count <= 4096, words.count < 16384 else { throw HitomiError.limitExceeded }
        if words[name] == nil {
            order.append(name); words[name] = .init(kind: "Word", score: 0)
        }
        if words[name]?.kind == "Short" {
            words[name]?.kind = "Word"
        }
        var record = words[name]!
        if record.mass.isEmpty {
            record.mass = record.relations.mapValues { Double($0) / 1000 }
        }
        for target in related where target != name && words[target] != nil {
            record.mass[target, default: 0] += 1
        }
        let keys = record.mass.keys.sorted(), sum = record.mass.values.reduce(0, +)
        var remaining = 1000
        record.relations.removeAll(keepingCapacity: true)
        for (index, key) in keys.enumerated() {
            let value = index == keys.count - 1 ? remaining : Int((record.mass[key]! / sum * 1000).rounded(.down))
            if value > 0 {
                record.relations[key] = value
            }
            remaining -= value
        }
        words[name] = record
    }

    mutating func notify(_ ownName: String, _ master: String) throws {
        for (kind, name) in [("Myself", ownName), ("Master", master)] where !name.isEmpty {
            guard name.utf8.count <= 4096 else { throw HitomiError.limitExceeded }
            for old in order where words[old]?.kind == kind && old != name {
                words.removeValue(forKey: old)
            }
            order.removeAll { words[$0] == nil }
            if words[name] == nil {
                order.append(name)
            }
            words[name] = .init(kind: kind, score: words[name]?.score ?? 0)
        }
    }
}

struct HitomiState: Codable, Equatable {
    var schemaVersion = 1
    var resources: [String: [String]]?
    var counters: [String: Int64] = [:]
    var savedWords: [String: [String]] = [:]
    var hearts = HitomiHearts()
}
