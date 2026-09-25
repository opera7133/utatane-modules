import Darwin
import Foundation
import MisakaCore
import ModuleProtocol

/// The conventional SHIORI interface owns one session per loaded library.
/// Utatane uses the optional internal bridge for independent sessions and SAORI services.
private final class ConventionalSession: @unchecked Sendable {
    static let shared = ConventionalSession()
    let lock = NSLock()
    var engine: NativeMisakaSession?
    var host: HostServices?
}

@_cdecl("loadu")
public func shioriLoadUTF8(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    defer { free(input) }
    guard let input, length > 0, length <= 8 * 1024 * 1024,
          let path = String(bytes: UnsafeRawBufferPointer(start: input, count: Int(length)), encoding: .utf8),
          path.hasPrefix("/"), !path.contains("\0") else { return 0 }
    let state = ConventionalSession.shared
    guard state.lock.try() else { return 0 }
    defer { state.lock.unlock() }
    // Do not silently replace a live ghost when a host loads the same library twice.
    guard state.engine == nil else { return 0 }
    do {
        let host = HostServices(nil)
        let master = URL(fileURLWithPath: path)
        let stateURL = try ModuleEnvironment.stateFile(
            named: "misaka-vars.json", legacyEnvironmentKey: "MISAKA_VARIABLE_STORE_PATH"
        )
        let engine = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: stateURL,
                                             saoriCaller: host, savesOnDeinit: false)
        guard host.failure == nil else { return 0 }
        state.host = host
        state.engine = engine
        return 1
    } catch { return 0 }
}

@_cdecl("load")
public func shioriLoad(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    shioriLoadUTF8(input, length)
}

@_cdecl("unload")
public func shioriUnload() -> Int32 {
    let state = ConventionalSession.shared
    guard state.lock.try() else { return 0 }
    defer { state.lock.unlock() }
    guard let engine = state.engine else { return 1 }
    do { try engine.save() }
    catch { return 0 }
    state.engine = nil
    state.host = nil
    return 1
}

@_cdecl("request")
public func shioriRequest(_ input: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    defer { free(input) }
    guard let length else { return nil }
    let count = length.pointee
    length.pointee = 0
    guard let input, count > 0, count <= 8 * 1024 * 1024,
          let wire = String(bytes: UnsafeRawBufferPointer(start: input, count: Int(count)), encoding: .utf8),
          !wire.contains("\0"), let request = try? ShioriMessageParser.parseRequest(wire),
          ["SHIORI/3.0", "PLUGIN/2.0"].contains(request.version),
          ["GET", "NOTIFY"].contains(request.method) else { return nil }
    let state = ConventionalSession.shared
    guard state.lock.try() else { return nil }
    defer { state.lock.unlock() }
    state.host?.failure = nil
    guard let engine = state.engine, let response = try? engine.request(request), state.host?.failure == nil else { return nil }
    let output = ShioriResponse(version: request.version, statusCode: response.statusCode,
                                reasonPhrase: response.reasonPhrase, headers: response.headers).serialized()
    let bytes = Array(output.utf8)
    guard bytes.count <= 8 * 1024 * 1024, let pointer = malloc(max(bytes.count, 1)) else { return nil }
    bytes.withUnsafeBytes { source in
        if let address = source.baseAddress {
            pointer.copyMemory(from: address, byteCount: bytes.count)
        }
    }
    length.pointee = Int32(bytes.count)
    return pointer
}
