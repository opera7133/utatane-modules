import Foundation
import LegacyText
import ModuleProtocol

public enum EseShioriError: LocalizedError, Sendable {
    case missingConfiguration(URL)

    public var errorDescription: String? {
        if case let .missingConfiguration(url) = self {
            return "ese-shiori設定が見つからない: \(url.path)"
        }
        return nil
    }
}

private struct PersistedState: Codable {
    var variables: [String: String]
    var storage: [Int: String]
    var learnedEntries: [String: [String]]?
    var talkInterval: Int?
    var talkSeconds: Int?
    var newsInterval: Int?
    var newsCounters: [String: Int]?
}

/// An ese-shiori session with no dependency on Utatane's event model.
public final class EseShioriSession {
    private var evaluator: EseEvaluator
    private let stateStoreURL: URL
    private let dictionaryCharset: String

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let ini = masterDirectoryURL.appending(path: "eseai.ini")
        guard FileManager.default.fileExists(atPath: ini.path) else { throw EseShioriError.missingConfiguration(ini) }
        let iniText = LegacyTextDecoder.decode(try Data(contentsOf: ini)) ?? ""
        let charset = Self.value(named: "DIC_CHAR_SET", in: iniText) ?? "Shift_JIS"
        dictionaryCharset = charset
        let configuredTalkInterval = Self.value(named: "RANDOM_TALK_INTERVAL", in: iniText).flatMap(Int.init)
        let dictionary = try EseDictionary.load(masterDirectoryURL: masterDirectoryURL, charset: charset)
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "ese-shiori-state.json")
        let saved = (try? Data(contentsOf: self.stateStoreURL))
            .flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        let fileDirectory = self.stateStoreURL.deletingLastPathComponent()
            .appending(path: "ese-shiori-files", directoryHint: .isDirectory)
        var fileContents = Self.textFiles(at: masterDirectoryURL, charset: charset)
        fileContents.merge(Self.textFiles(at: fileDirectory, charset: charset)) { _, stateValue in stateValue }
        evaluator = EseEvaluator(
            dictionary: dictionary,
            storage: saved?.storage ?? [:],
            variables: saved?.variables ?? [:],
            learnedEntries: saved?.learnedEntries ?? [:],
            talkInterval: saved?.talkInterval ?? configuredTalkInterval,
            talkSeconds: saved?.talkSeconds ?? 0,
            newsInterval: saved?.newsInterval ?? Self.value(named: "NEWS_READ_INTERVAL", in: iniText).flatMap(Int.init),
            newsCounters: saved?.newsCounters ?? [:],
            dictionaryCharset: charset,
            fileContents: fileContents
        )
        for (name, values) in evaluator.learnedEntries {
            evaluator.dictionary.entries[name, default: []].append(contentsOf: values)
        }
        evaluator.variables["selfname"] = Self.descriptValue("name", at: masterDirectoryURL) ?? ""
        evaluator.variables["keroname"] = Self.descriptValue("name2", at: masterDirectoryURL) ?? ""
    }

    public func request(_ request: ShioriRequest, charset: String = "UTF-8") throws -> ShioriResponse {
        if request.id?.caseInsensitiveCompare("OnUserInput") == .orderedSame,
           request.reference(0)?.caseInsensitiveCompare("SetUsername") == .orderedSame,
           let text = request.reference(1)
        {
            evaluator.variables["username"] = text
        }
        let value = LegacyMateriaScriptNormalizer.normalizeKeroSurfaces(in: evaluator.response(for: request))
        try flushPendingFileWrites()
        if request.id?.caseInsensitiveCompare("OnClose") == .orderedSame {
            try save()
        }
        let script: String
        if let target = evaluator.reflectedTarget, !value.isEmpty {
            script = "\\![otherghosttalk,\(Self.quotedArgument(target)),\(Self.quotedArgument(value))]"
        } else {
            script = value
        }
        var headers = ShioriHeaders([.init(name: "Charset", value: charset)])
        if !script.isEmpty {
            headers.append(name: "Value", value: script)
        }
        return ShioriResponse(
            version: request.version,
            statusCode: script.isEmpty ? 204 : 200,
            reasonPhrase: script.isEmpty ? "No Content" : "OK",
            headers: headers
        )
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: stateStoreURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(PersistedState(
            variables: evaluator.variables,
            storage: evaluator.storage,
            learnedEntries: evaluator.learnedEntries,
            talkInterval: evaluator.talkInterval,
            talkSeconds: evaluator.talkSeconds,
            newsInterval: evaluator.newsInterval,
            newsCounters: evaluator.newsCounters
        )).write(to: stateStoreURL, options: .atomic)
    }

    private func flushPendingFileWrites() throws {
        guard !evaluator.pendingFileWrites.isEmpty else { return }
        let directory = stateStoreURL.deletingLastPathComponent()
            .appending(path: "ese-shiori-files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (filename, value) in evaluator.pendingFileWrites {
            let safeName = URL(filePath: filename).lastPathComponent
            guard !safeName.isEmpty, safeName != ".", safeName != "..",
                  let data = LegacyTextDecoder.encode(value, charset: dictionaryCharset)
            else { continue }
            try data.write(to: directory.appending(path: safeName), options: .atomic)
        }
        evaluator.pendingFileWrites.removeAll()
    }

    private static func value(named name: String, in text: String) -> String? {
        text.components(separatedBy: .newlines).compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame
            else { return nil }
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }.first
    }

    private static func textFiles(at directory: URL, charset: String) -> [String: String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [:] }
        return files.reduce(into: [:]) { result, file in
            let allowedExtensions = ["txt", "dat", "ini", "log"]
            guard !file.hasDirectoryPath, allowedExtensions.contains(file.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: file), data.count <= 4 * 1024 * 1024,
                  let text = LegacyTextDecoder.decode(data, preferredCharset: charset)
            else { return }
            result[file.lastPathComponent] = text
        }
    }

    private static func quotedArgument(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func descriptValue(_ key: String, at master: URL) -> String? {
        let url = master.appending(path: "descript.txt")
        guard let data = try? Data(contentsOf: url), let text = LegacyTextDecoder.decode(data) else { return nil }
        return text.components(separatedBy: .newlines)
            .first { $0.hasPrefix(key + ",") }
            .map { String($0.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
