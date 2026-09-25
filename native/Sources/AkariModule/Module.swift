import Darwin
import Foundation
import LegacyText
import ModuleProtocol
import AkariCore

private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

private func waitFor<Value: Sendable>(_ body: @Sendable @escaping () async throws -> Value) -> Value? {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<Value>()
    Task.detached {
        box.value = try? await body()
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 30) == .success else { return nil }
    return box.value
}

private final class Session: @unchecked Sendable {
    static let shared = Session()
    let lock = NSLock()
    var engine: AkariSession?
}

private func load(_ input: UnsafeMutableRawPointer?, _ length: Int32, utf8Only: Bool) -> Int32 {
    defer { free(input) }
    guard let input, length > 0, length <= 8 * 1024 * 1024 else { return 0 }
    let data = Data(bytes: input, count: Int(length))
    let path = utf8Only ? String(data: data, encoding: .utf8)
        : String(data: data, encoding: .utf8) ?? LegacyTextDecoder.decode(data, preferredCharset: "Shift_JIS")
    guard let path, path.hasPrefix("/"), !path.contains("\0") else { return 0 }
    let session = Session.shared
    guard session.lock.try() else { return 0 }
    defer { session.lock.unlock() }
    guard session.engine == nil else { return 0 }
    let stateURL: URL?
    if let statePath = ProcessInfo.processInfo.environment["AKARI_VARIABLE_STORE_PATH"] {
        guard statePath.hasPrefix("/"), !statePath.contains("\0") else { return 0 }
        stateURL = URL(fileURLWithPath: statePath)
    } else {
        stateURL = nil
    }
    session.engine = try? AkariSession(
        masterDirectoryURL: URL(fileURLWithPath: path),
        variableStoreURL: stateURL
    )
    return session.engine == nil ? 0 : 1
}

@_cdecl("loadu")
public func akariLoadUTF8(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    load(input, length, utf8Only: true)
}

@_cdecl("load")
public func akariLoad(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    load(input, length, utf8Only: false)
}

@_cdecl("unload")
public func akariUnload() -> Int32 {
    let session = Session.shared
    guard session.lock.try() else { return 0 }
    defer { session.lock.unlock() }
    guard let engine = session.engine else { return 1 }
    guard waitFor({ await engine.waitForBackgroundTasks(); try await engine.shutdown(); return true }) == true else { return 0 }
    session.engine = nil
    return 1
}

@_cdecl("request")
public func akariRequest(_ input: UnsafeMutableRawPointer?,
                        _ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
{
    defer { free(input) }
    guard let length else { return nil }
    let count = length.pointee
    length.pointee = 0
    guard let input, count > 0, count <= 8 * 1024 * 1024 else { return nil }
    let data = Data(bytes: input, count: Int(count))
    guard data.suffix(4).elementsEqual([13, 10, 13, 10]), !data.contains(0),
          let ascii = String(data: data, encoding: .isoLatin1) else { return nil }
    let header = ascii.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("charset:") }
    let requestedCharset = header?.split(separator: ":", maxSplits: 1).last?
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "shift_jis"
    let charset: String
    switch requestedCharset {
    case "utf-8", "utf8": charset = "UTF-8"
    case "shift_jis", "shift-jis", "cp932", "windows-31j": charset = "Shift_JIS"
    default: return nil
    }
    guard let wire = LegacyTextDecoder.decode(data, preferredCharset: charset),
          !wire.contains("\0"),
          let request = try? ShioriMessageParser.parseRequest(wire),
          request.version == "SHIORI/3.0", ["GET", "NOTIFY"].contains(request.method)
    else { return nil }
    let session = Session.shared
    guard session.lock.try() else { return nil }
    defer { session.lock.unlock() }
    guard let engine = session.engine,
          let response = waitFor({ try await engine.request(request, charset: charset) }),
          let encoded = LegacyTextDecoder.encode(response.serialized(), charset: charset),
          encoded.count <= 8 * 1024 * 1024,
          let pointer = malloc(max(encoded.count, 1))
    else { return nil }
    encoded.withUnsafeBytes { bytes in
        if let address = bytes.baseAddress {
            pointer.copyMemory(from: address, byteCount: bytes.count)
        }
    }
    length.pointee = Int32(encoded.count)
    return pointer
}
