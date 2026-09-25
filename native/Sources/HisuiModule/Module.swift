import Darwin
import Foundation
import LegacyText
import ModuleProtocol
import HisuiCore

private final class Session: @unchecked Sendable {
    static let shared = Session()
    let lock = NSLock()
    var engine: HisuiSession?
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
    do {
        stateURL = try ModuleEnvironment.stateFile(
            named: "hisui-state.json", legacyEnvironmentKey: "HISUI_STATE_PATH"
        )
    } catch { return 0 }
    session.engine = try? HisuiSession(
        masterDirectoryURL: URL(fileURLWithPath: path),
        stateStoreURL: stateURL
    )
    return session.engine == nil ? 0 : 1
}

@_cdecl("loadu")
public func hisuiLoadUTF8(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    load(input, length, utf8Only: true)
}

@_cdecl("load")
public func hisuiLoad(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    load(input, length, utf8Only: false)
}

@_cdecl("unload")
public func hisuiUnload() -> Int32 {
    let session = Session.shared
    guard session.lock.try() else { return 0 }
    defer { session.lock.unlock() }
    guard let engine = session.engine else { return 1 }
    do { try engine.save() } catch { return 0 }
    session.engine = nil
    return 1
}

@_cdecl("request")
public func hisuiRequest(_ input: UnsafeMutableRawPointer?,
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
          let response = try? engine.request(request, charset: charset),
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
