import Foundation
import LegacyText
import ModuleProtocol

private struct YuhnaRule: Sendable {
    let condition: String?
    let scripts: [String]
}

private struct YuhnaState: Codable, Sendable {
    var variables: [String: String] = [:]
    var talkInterval = 180
}

public final class YuhnaSession {
    private let events: [String: [YuhnaRule]]
    private let stateStoreURL: URL
    private var state: YuhnaState
    private var talkSeconds = 0
    private var selfName = ""
    private var strokeKey: String?
    private var strokeCount = 0

    public let loadedEventCount: Int
    public let loadedRuleCount: Int
    public let conditionalRuleCount: Int
    public let skippedEventCount: Int

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let dictionaryURL = masterDirectoryURL.appending(path: "dic.ydf")
        let parsed = try YuhnaDictionaryParser.parse(Data(contentsOf: dictionaryURL))
        events = parsed.events
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "yuhna-state.json")
        state = (try? JSONDecoder().decode(YuhnaState.self, from: Data(contentsOf: self.stateStoreURL)))
            ?? YuhnaState()
        loadedEventCount = parsed.events.count
        loadedRuleCount = parsed.loadedRecords
        conditionalRuleCount = parsed.conditionalRecords
        skippedEventCount = parsed.skipped
        selfName = Self.loadSelfName(masterDirectoryURL)
    }

    public func request(_ request: ShioriRequest, charset: String = "UTF-8") throws -> ShioriResponse {
        let id = eventID(for: request)
        if request.id?.caseInsensitiveCompare("OnMouseMove") == .orderedSame {
            guard let region = request.reference(4) else {
                resetStroke()
                return response(nil, for: request, charset: charset)
            }
            let key = "\(request.reference(3) ?? "0"):\(region.lowercased())"
            strokeCount = strokeKey == key ? strokeCount + 1 : 1
            strokeKey = key
            guard strokeCount >= 50 else { return response(nil, for: request, charset: charset) }
            resetStroke()
        } else if ["OnMouseLeave", "OnMouseLeaveAll"].contains(request.id ?? "") {
            resetStroke()
        }
        if id.caseInsensitiveCompare("OnYuhnaUsername") == .orderedSame,
           let username = request.reference(0), !username.isEmpty
        {
            state.variables["username"] = username
            try saveState()
        }
        if id.caseInsensitiveCompare("OnSecondChange") == .orderedSame {
            talkSeconds += 1
        }
        let selector = request.reference(0)
        let matchingRules = events.flatMap { name, rules in
            let targetsEvent = name.caseInsensitiveCompare(id) == .orderedSame
            return rules.filter { rule in
                guard let condition = rule.condition else { return targetsEvent }
                let selectorDispatch = condition.contains("%sel") && selector != nil
                return (targetsEvent || selectorDispatch) && matches(condition, request: request)
            }
        }
        let preferredRules = matchingRules.filter { $0.condition != nil }
        var selectedRules = preferredRules.isEmpty ? matchingRules : preferredRules
        if selectedRules.isEmpty,
           id.caseInsensitiveCompare("OnSecondChange") == .orderedSame,
           state.talkInterval > 0,
           talkSeconds >= state.talkInterval
        {
            talkSeconds = 0
            selectedRules = events.first {
                $0.key.caseInsensitiveCompare("OnYuhnaRandomTalk") == .orderedSame
            }?.value ?? []
        }
        guard let rule = selectedRules.randomElement(), var value = rule.scripts.randomElement() else {
            // OnSecondChange is handled by the native interval counter even when it does not speak.
            // Returning an empty script prevents a configured Wine fallback from running a second timer.
            return response(nil, for: request, charset: charset)
        }
        for index in 0 ... 31 {
            value = value.replacingOccurrences(of: "%ref\(index)", with: request.reference(index) ?? "")
        }
        value = value.replacingOccurrences(of: "%selfname", with: selfName)
        value = value.replacingOccurrences(of: "%username", with: state.variables["username", default: ""])
        let expanded = expandVariables(in: value)
        value = expanded.value
        if let interval = firstCapture(pattern: #"\$i\[([0-9]+)\]"#, in: value).flatMap(Int.init) {
            state.talkInterval = interval
            talkSeconds = 0
            try saveState()
        } else if expanded.changed {
            try saveState()
        }
        value = value.replacingOccurrences(of: #"\$i\[[0-9]+\]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(
            of: "$n",
            with: #"\![open,inputbox,OnYuhnaUsername,0]"#
        )
        return response(value, for: request, charset: charset)
    }

    public func save() throws {
        try saveState()
    }

    private func response(_ value: String?, for request: ShioriRequest, charset: String) -> ShioriResponse {
        var headers = ShioriHeaders([.init(name: "Charset", value: charset)])
        if let value, !value.isEmpty { headers.append(name: "Value", value: value) }
        let hasValue = value?.isEmpty == false
        return ShioriResponse(version: request.version, statusCode: hasValue ? 200 : 204,
                              reasonPhrase: hasValue ? "OK" : "No Content", headers: headers)
    }

    private func eventID(for request: ShioriRequest) -> String {
        let id = request.id ?? ""
        let scope = request.reference(3) ?? "0"
        switch id.lowercased() {
        case "onaitalk": return "OnYuhnaRandomTalk"
        case "onmouseclick", "onmouseclickex": return "OnYuhnaMouseClick\(scope)"
        case "onmousedoubleclick", "onmousedoubleclickex", "onmousemultipleclick", "onmousemultipleclickex":
            return "OnYuhnaMouseDoubleClick\(scope)"
        case "onmousemove": return "OnYuhnaMouseTouch\(scope)"
        case "onmousewheel": return "OnYuhnaMouseWheel\(scope)"
        default: return id
        }
    }

    private func matches(_ source: String, request: ShioriRequest) -> Bool {
        source.components(separatedBy: "&").allSatisfy { expression in
            let value = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            for rawOperator in ["!=", ">=", "=>", "="] {
                guard let range = value.range(of: rawOperator) else { continue }
                let left = resolve(String(value[..<range.lowerBound]), request: request)
                let right = resolve(String(value[range.upperBound...]), request: request)
                switch rawOperator {
                case "!=": return left.caseInsensitiveCompare(right) != .orderedSame
                case ">=", "=>":
                    guard let lhs = Double(left), let rhs = Double(right) else { return false }
                    return lhs >= rhs
                default: return left.caseInsensitiveCompare(right) == .orderedSame
                }
            }
            return false
        }
    }

    private func resolve(_ source: String, request: ShioriRequest) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "%sel" {
            return request.reference(0) ?? ""
        }
        if value.hasPrefix("%ref"), let index = Int(value.dropFirst(4)) {
            return request.reference(index) ?? ""
        }
        if value == "%selfname" {
            return selfName
        }
        if value == "%username" {
            return state.variables["username", default: ""]
        }
        if value.hasPrefix("{"), value.hasSuffix("}") {
            return state.variables[String(value.dropFirst().dropLast()), default: "0"]
        }
        return value
    }

    private func expandVariables(in source: String) -> (value: String, changed: Bool) {
        var output = source
        var changed = false
        let assignmentPattern = #"\{([A-Za-z_][A-Za-z0-9_]*)=([^{}]+)\}"#
        while let regex = try? NSRegularExpression(pattern: assignmentPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let wholeRange = Range(match.range(at: 0), in: output),
              let nameRange = Range(match.range(at: 1), in: output),
              let expressionRange = Range(match.range(at: 2), in: output)
        {
            let name = String(output[nameRange])
            let expression = String(output[expressionRange])
            state.variables[name] = evaluateExpression(expression)
            output.replaceSubrange(wholeRange, with: "")
            changed = true
        }
        guard let variableRegex = try? NSRegularExpression(pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#)
        else { return (output, changed) }
        while let match = variableRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let wholeRange = Range(match.range(at: 0), in: output),
              let nameRange = Range(match.range(at: 1), in: output)
        {
            let name = String(output[nameRange])
            output.replaceSubrange(wholeRange, with: state.variables[name, default: "0"])
        }
        return (output, changed)
    }

    private func evaluateExpression(_ source: String) -> String {
        let expression = source.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        if expression == "%[d6]" {
            return String(Int.random(in: 1 ... 6))
        }
        let terms = expression.split(separator: "+").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !terms.isEmpty,
              terms.allSatisfy({ Int($0) != nil || state.variables[$0].flatMap(Int.init) != nil })
        else { return state.variables[expression, default: expression] }
        return String(terms.reduce(0) { result, term in
            result + (Int(term) ?? state.variables[term].flatMap(Int.init) ?? 0)
        })
    }

    private func saveState() throws {
        try FileManager.default.createDirectory(
            at: stateStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: stateStoreURL, options: .atomic)
    }

    private func resetStroke() {
        strokeKey = nil
        strokeCount = 0
    }

    private func firstCapture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private static func loadSelfName(_ directory: URL) -> String {
        guard let data = try? Data(contentsOf: directory.appending(path: "descript.txt")),
              let source = LegacyTextDecoder.decode(data)
        else { return "" }
        for line in source.components(separatedBy: .newlines) {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == "sakura.name" {
                return parts[1]
            }
        }
        return ""
    }
}

private enum YuhnaDictionaryParser {
    struct Result {
        let events: [String: [YuhnaRule]]
        let loadedRecords: Int
        let conditionalRecords: Int
        let skipped: Int
    }

    static func parse(_ data: Data) throws -> Result {
        guard data.starts(with: Data("YDF/1.07".utf8)),
              let randomName = data.range(of: Data("OnYuhnaRandomTalk".utf8)),
              randomName.lowerBound >= 6
        else { throw CocoaError(.fileReadCorruptFile) }
        var cursor = randomName.lowerBound - 2
        let declaredCountOffset = cursor - 4
        let declaredCount = Int(readUInt32(data, at: declaredCountOffset) ?? 0)
        guard declaredCount > 0, declaredCount < 10000 else { throw CocoaError(.fileReadCorruptFile) }

        var events: [String: [YuhnaRule]] = [:]
        var loadedRecords = 0
        var skipped = 0
        for _ in 0 ..< declaredCount {
            guard let record = parseRecord(data, at: cursor) else {
                skipped += 1
                guard let next = nextEventRecord(in: data, after: cursor) else { break }
                cursor = next
                continue
            }
            cursor = record.end
            if !record.scripts.isEmpty {
                events[record.name, default: []].append(YuhnaRule(condition: nil, scripts: record.scripts))
                loadedRecords += 1
            }
        }
        let conditionalRecords = parseConditionalRecords(data)
        for record in conditionalRecords {
            events[record.name, default: []].append(YuhnaRule(condition: record.condition, scripts: record.scripts))
            loadedRecords += 1
        }
        guard !events.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return Result(
            events: events,
            loadedRecords: loadedRecords,
            conditionalRecords: conditionalRecords.count,
            skipped: max(skipped, declaredCount - loadedRecords)
        )
    }

    private static func parseConditionalRecords(
        _ data: Data
    ) -> [(name: String, condition: String, scripts: [String])] {
        var records: [(name: String, condition: String, scripts: [String])] = []
        var start = 0
        while start < data.count {
            guard let record = parseConditionalRecord(data, at: start) else {
                start += 1
                continue
            }
            records.append(record.value)
            start = record.end
        }
        return records
    }

    private static func parseConditionalRecord(
        _ data: Data,
        at start: Int
    ) -> (value: (name: String, condition: String, scripts: [String]), end: Int)? {
        var cursor = start
        guard let rawLabelLength = readUInt16(data, at: cursor) else { return nil }
        let labelLength = Int(rawLabelLength)
        cursor += 2
        guard labelLength > 0,
              let labelBytes = slice(data, at: cursor, count: labelLength),
              let label = LegacyTextDecoder.decode(labelBytes),
              let eventMarker = label.range(of: "@On", options: .backwards)
        else { return nil }
        let eventName = String(label[eventMarker.lowerBound...].dropFirst())
        cursor += labelLength

        guard let rawParentLength = readUInt16(data, at: cursor) else { return nil }
        let parentLength = Int(rawParentLength)
        cursor += 2
        guard parentLength > 0,
              let parentBytes = slice(data, at: cursor, count: parentLength),
              let parent = LegacyTextDecoder.decode(parentBytes),
              parent == eventName || parent.hasSuffix("@\(eventName)")
        else { return nil }
        cursor += parentLength

        guard cursor < data.count else { return nil }
        let conditionLength = Int(data[cursor])
        cursor += 1
        guard conditionLength > 0,
              let conditionBytes = slice(data, at: cursor, count: conditionLength),
              let condition = LegacyTextDecoder.decode(conditionBytes),
              condition.contains("%")
        else { return nil }
        cursor += conditionLength

        guard cursor < data.count else { return nil }
        let aliasCount = Int(data[cursor])
        cursor += 1
        guard aliasCount <= 64 else { return nil }
        for _ in 0 ..< aliasCount {
            guard cursor < data.count else { return nil }
            let aliasLength = Int(data[cursor])
            cursor += 1
            guard slice(data, at: cursor, count: aliasLength) != nil else { return nil }
            cursor += aliasLength
        }

        guard cursor < data.count else { return nil }
        let candidateCount = Int(data[cursor])
        cursor += 1
        guard candidateCount > 0, candidateCount <= 64 else { return nil }
        var scripts: [String] = []
        for _ in 0 ..< candidateCount {
            guard let length = readUInt16(data, at: cursor) else { return nil }
            cursor += 2
            guard cursor < data.count, data[cursor] == 0 else { return nil }
            cursor += 1
            guard let bytes = slice(data, at: cursor, count: Int(length)),
                  let script = LegacyTextDecoder.decode(bytes)
            else { return nil }
            cursor += Int(length)
            scripts.append(script.replacingOccurrences(of: "¥", with: "\\"))
        }
        return ((eventName, condition, scripts), cursor)
    }

    private static func parseRecord(_ data: Data, at start: Int) -> (name: String, scripts: [String], end: Int)? {
        guard let nameLength = readUInt16(data, at: start), nameLength > 0, nameLength < 128 else { return nil }
        var cursor = start + 2
        guard let nameData = slice(data, at: cursor, count: Int(nameLength)),
              let name = String(data: nameData, encoding: .ascii),
              name.hasPrefix("On") || name.hasPrefix("@On")
        else { return nil }
        cursor += Int(nameLength)
        guard cursor + 4 <= data.count else { return nil }
        let candidateCount: UInt32
        if data[cursor] == 1 {
            cursor += 1
            guard let count = readUInt32(data, at: cursor), count <= 256 else { return nil }
            candidateCount = count
            cursor += 4
        } else {
            guard let aliasCount = readUInt32(data, at: cursor), aliasCount <= 256 else { return nil }
            cursor += 4
            for _ in 0 ..< aliasCount {
                guard cursor < data.count else { return nil }
                let aliasLength = Int(data[cursor])
                cursor += 1
                guard slice(data, at: cursor, count: aliasLength) != nil else { return nil }
                cursor += aliasLength
            }
            guard cursor < data.count else { return nil }
            candidateCount = UInt32(data[cursor])
            cursor += 1
        }
        var scripts: [String] = []
        for _ in 0 ..< candidateCount {
            guard let length = readUInt16(data, at: cursor) else { return nil }
            cursor += 2
            guard cursor < data.count, data[cursor] == 0 else { return nil }
            cursor += 1
            guard let bytes = slice(data, at: cursor, count: Int(length)),
                  let script = LegacyTextDecoder.decode(bytes)
            else { return nil }
            cursor += Int(length)
            scripts.append(script.replacingOccurrences(of: "¥", with: "\\"))
        }
        return (name, scripts, cursor)
    }

    private static func nextEventRecord(in data: Data, after offset: Int) -> Int? {
        var cursor = offset + 1
        while cursor + 8 < data.count {
            if let length = readUInt16(data, at: cursor), length >= 4, length < 128,
               let nameData = slice(data, at: cursor + 2, count: Int(length)),
               let name = String(data: nameData, encoding: .ascii),
               name.hasPrefix("On") || name.hasPrefix("@On")
            {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func slice(_ data: Data, at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        return data.subdata(in: offset ..< offset + count)
    }
}
