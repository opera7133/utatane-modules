import CXPath
import Foundation

private final class XPathValues {
    var values: [String] = []
    var byteCount = 0
    func append(_ bytes: UnsafePointer<CChar>?, count: Int) -> Int32 {
        guard let bytes, count <= 2 * 1024 * 1024 - byteCount, values.count < 8192 else { return 0 }
        values.append(String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self))
        byteCount += count
        return 1
    }
}

final class NativeXPath: NativeSaoriModule {
    private struct Document {
        let path: String
        let pointer: UnsafeMutableRawPointer
        let byteCount: Int
    }
    private let directory: URL
    private var documents: [Int32: Document] = [:]
    private var nextID: Int32 = 1
    private var totalBytes = 0

    init(directory: URL) { self.directory = directory }

    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let command = arguments.first?.lowercased(), arguments.count >= 2 else { return .init(400) }
        if command == "open" {
            let path = arguments[1]
            if let existing = documents.first(where: { $0.value.path == path }) { return .init(200, [String(existing.key)]) }
            guard documents.count < 32, nextID < Int32.max else { return .init(400) }
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
            let url = normalized.hasPrefix("/") ? URL(filePath: normalized) : directory.appending(path: normalized)
            guard let file = try? FileHandle(forReadingFrom: url) else { return .init(400) }
            defer { try? file.close() }
            guard let data = try? file.read(upToCount: 8 * 1024 * 1024 + 1), !data.isEmpty,
                  data.count <= 8 * 1024 * 1024, totalBytes + data.count <= 32 * 1024 * 1024 else { return .init(400) }
            let pointer = data.withUnsafeBytes { bytes in
                utatane_xpath_open(bytes.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(data.count))
            }
            guard let pointer else { return .init(400) }
            let id = nextID; nextID += 1
            documents[id] = .init(path: path, pointer: pointer, byteCount: data.count)
            totalBytes += data.count
            return .init(200, [String(id)])
        }
        guard let id = Int32(arguments[1]), let document = documents[id] else { return .init(400) }
        if command == "close" {
            utatane_xpath_close(document.pointer); documents[id] = nil; totalBytes -= document.byteCount
            return .init(204)
        }
        guard command == "get", arguments.count >= 3, arguments[2].utf8.count <= 4096 else { return .init(400) }
        let collected = XPathValues()
        var nodes: Int32 = 0
        let context = Unmanaged.passUnretained(collected).toOpaque()
        let success = arguments[2].withCString { expression in
            utatane_xpath_get(document.pointer, expression, &nodes, context) { context, bytes, count in
                guard let context else { return 0 }
                return Unmanaged<XPathValues>.fromOpaque(context).takeUnretainedValue().append(bytes, count: count)
            }
        }
        guard success != 0 else { return .init(500) }
        let result = nodes != 0 ? collected.values.joined(separator: "\u{1}") : collected.values.first ?? ""
        return .init(200, [result] + collected.values)
    }

    func call(_ arguments: [String]) -> String { execute(arguments).values.first ?? "" }
    func unload() {
        for document in documents.values { utatane_xpath_close(document.pointer) }
        documents.removeAll(); totalBytes = 0
    }
    deinit { unload() }
}
