import Foundation
import LegacyText
import ModuleProtocol

/// A SHIORI session independent of any baseware's event model.
public final class NiseShioriSession {
    private let stateStoreURL: URL
    private var evaluator: NiseEvaluator

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let dictionary = try NiseDictionary.load(from: masterDirectoryURL)
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "nise-shiori-state.json")
        let state = (try? Data(contentsOf: self.stateStoreURL))
            .flatMap { try? JSONDecoder().decode(NisePersistedState.self, from: $0) } ?? .init()
        let names = Self.description(at: masterDirectoryURL)
        evaluator = NiseEvaluator(
            dictionary: dictionary,
            state: state,
            selfName: names["sakura.name"] ?? names["name"] ?? "",
            keroName: names["kero.name"] ?? names["name2"] ?? ""
        )
        for (key, values) in state.learnedWords {
            evaluator.dictionary.words[key, default: []].append(contentsOf: values)
        }
    }

    public func request(_ request: ShioriRequest, charset: String = "UTF-8") throws -> ShioriResponse {
        let value = evaluator.response(for: request)
        let communicateTarget = evaluator.communicateTarget
        evaluator.communicateTarget = nil
        try save()
        var headers = ShioriHeaders([.init(name: "Charset", value: charset)])
        if let value, !value.isEmpty {
            headers.append(name: "Value", value: value)
        }
        if let communicateTarget {
            headers.append(name: "Reference0", value: communicateTarget)
        }
        let hasContent = (value?.isEmpty == false) || communicateTarget != nil
        return ShioriResponse(version: request.version,
                              statusCode: hasContent ? 200 : 204,
                              reasonPhrase: hasContent ? "OK" : "No Content",
                              headers: headers)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: stateStoreURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(evaluator.state).write(to: stateStoreURL, options: .atomic)
    }

    private static func description(at directory: URL) -> [String: String] {
        let url = directory.appending(path: "descript.txt")
        guard let data = try? Data(contentsOf: url), let source = LegacyTextDecoder.decode(data) else { return [:] }
        return source.components(separatedBy: .newlines).reduce(into: [:]) { result, line in
            let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return }
            result[fields[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
