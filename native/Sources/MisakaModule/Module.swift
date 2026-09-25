import CMisakaHostBridge
import Darwin
import Foundation
import MisakaCore
import ModuleProtocol

private final class Session: @unchecked Sendable {
    let lock = NSLock()
    let engine: NativeMisakaSession
    let host: HostServices
    var closed = false
    init(_ engine: NativeMisakaSession, _ host: HostServices) {
        self.engine = engine; self.host = host
    }
}

private final class Registry: @unchecked Sendable {
    static let shared = Registry()
    let lock = NSLock()
    var sessions: [UInt64: Session] = [:]
    var next: UInt64 = 1
    func get(_ id: UInt64) -> Session? {
        lock.withLock { sessions[id] }
    }

    func add(_ session: Session) -> UInt64 {
        lock.withLock {
            // Never recycle an ID while the library is loaded.
            guard next < UInt64.max else { return 0 }
            let id = next; next += 1; sessions[id] = session; return id
        }
    }

    func remove(_ id: UInt64) {
        lock.withLock { _ = sessions.removeValue(forKey: id) }
    }
}

private func empty(_ output: UnsafeMutablePointer<UMBuffer>?) -> Bool {
    guard let output else { return false }
    return output.pointee.data == nil && output.pointee.length == 0
}

private func emit(_ text: String, _ output: UnsafeMutablePointer<UMBuffer>, code: Int32) -> Int32 {
    let bytes = Array(text.utf8)
    guard bytes.count <= Int(UM_MAX_BYTES) else { return 1 }
    if bytes.isEmpty {
        return code
    }
    guard let pointer = malloc(bytes.count)?.assumingMemoryBound(to: UInt8.self) else { return 7 }
    pointer.initialize(from: bytes, count: bytes.count)
    output.pointee = UMBuffer(data: pointer, length: UInt32(bytes.count))
    return code
}

private func path(_ bytes: UMBytes) -> URL? {
    guard bytes.length > 0, bytes.length <= UM_MAX_BYTES, let pointer = bytes.data,
          let string = String(bytes: UnsafeBufferPointer(start: pointer, count: Int(bytes.length)), encoding: .utf8),
          string.hasPrefix("/"), !string.contains("\0") else { return nil }
    return URL(fileURLWithPath: string).standardizedFileURL.resolvingSymlinksInPath()
}

@_cdecl("um_api_version") public func moduleVersion() -> UInt32 {
    1
}

@_cdecl("um_release") public func moduleRelease(_ buffer: UnsafeMutablePointer<UMBuffer>?) {
    guard let buffer else { return }
    free(buffer.pointee.data)
    buffer.pointee = UMBuffer()
}

@_cdecl("um_create")
public func moduleCreate(_ config: UnsafePointer<UMConfig>?, _ host: UnsafePointer<UMHostV1>?,
                         _ id: UnsafeMutablePointer<UInt64>?, _ error: UnsafeMutablePointer<UMBuffer>?) -> Int32
{
    guard let id, let error, empty(error), let config else { return 1 }
    id.pointee = 0
    guard config.pointee.abi_version == 1, config.pointee.struct_size >= MemoryLayout<UMConfig>.size else { return 2 }
    if let host {
        guard host.pointee.abi_version == 1, host.pointee.struct_size >= MemoryLayout<UMHostV1>.size else { return 2 }
        guard (host.pointee.saori == nil) == (host.pointee.release == nil) else { return 1 }
    }
    guard let master = path(config.pointee.master_path), let state = path(config.pointee.state_path),
          state != master, !state.path.hasPrefix(master.path + "/")
    else {
        return emit("Expected absolute paths and a state file outside the ghost master directory", error, code: 1)
    }
    let services = HostServices(host?.pointee)
    do {
        let stateFile = state.lastPathComponent == "module-state.json"
            ? state.deletingLastPathComponent().appending(path: "misaka-vars.json") : state
        let oldPluginState = master.appending(path: "misaka_vars.json")
        if !FileManager.default.fileExists(atPath: stateFile.path),
           FileManager.default.fileExists(atPath: oldPluginState.path),
           (try oldPluginState.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: oldPluginState, to: stateFile)
        }
        let engine = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: stateFile,
                                             saoriCaller: services, savesOnDeinit: false)
        if let failure = services.failure {
            return emit(failure, error, code: 6)
        }
        let identity = Registry.shared.add(Session(engine, services))
        guard identity != 0 else { return emit("Session IDs exhausted", error, code: 5) }
        id.pointee = identity
        return 0
    } catch let failure { return emit(failure.localizedDescription, error, code: 5) }
}

@_cdecl("um_request")
public func moduleRequest(_ id: UInt64, _ bytes: UnsafePointer<UInt8>?, _ length: UInt32,
                          _ response: UnsafeMutablePointer<UMBuffer>?) -> Int32
{
    guard let response, empty(response), let bytes, length > 0, length <= UM_MAX_BYTES else { return 1 }
    guard let session = Registry.shared.get(id) else { return 3 }
    guard session.lock.try() else { return 4 }
    defer { session.lock.unlock() }
    guard !session.closed else { return 3 }
    // Protocol bytes use UTF-8; dictionary encoding is independent.
    guard let wire = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(length)), encoding: .utf8),
          !wire.contains("\0"), wire.hasSuffix("\r\n\r\n"),
          !wire.replacingOccurrences(of: "\r\n", with: "").contains(where: { $0 == "\r" || $0 == "\n" }),
          wire.range(of: "\r\n\r\n")?.upperBound == wire.endIndex,
          let request = try? ShioriMessageParser.parseRequest(wire), ["SHIORI/3.0", "PLUGIN/2.0"].contains(request.version),
          ["GET", "NOTIFY"].contains(request.method),
          (request.headers["Charset"] ?? "UTF-8").uppercased() == "UTF-8"
    else {
        return emit("Expected a UTF-8 SHIORI/3.0 or PLUGIN/2.0 request with CRLF and a final blank line", response, code: 1)
    }
    session.host.failure = nil
    do {
        let result = try session.engine.request(request)
        if let failure = session.host.failure {
            return emit(failure, response, code: 6)
        }
        let wireResponse = ShioriResponse(version: request.version, statusCode: result.statusCode,
                                          reasonPhrase: result.reasonPhrase, headers: result.headers)
        return emit(wireResponse.serialized(), response, code: 0)
    } catch { return emit(error.localizedDescription, response, code: 5) }
}

@_cdecl("um_destroy")
public func moduleDestroy(_ id: UInt64, _ error: UnsafeMutablePointer<UMBuffer>?) -> Int32 {
    guard let error, empty(error) else { return 1 }
    guard let session = Registry.shared.get(id) else { return 3 }
    guard session.lock.try() else { return 4 }
    defer { session.lock.unlock() }
    guard !session.closed else { return 3 }
    do { try session.engine.save() }
    catch let failure { return emit(failure.localizedDescription, error, code: 5) }
    session.closed = true
    Registry.shared.remove(id)
    return 0
}

@_cdecl("um_discard")
public func moduleDiscard(_ id: UInt64) -> Int32 {
    guard let session = Registry.shared.get(id) else { return 3 }
    guard session.lock.try() else { return 4 }
    defer { session.lock.unlock() }
    guard !session.closed else { return 3 }
    session.closed = true
    Registry.shared.remove(id)
    return 0
}

/// Identifies this Swift image for content-based reuse by the Utatane loader.
@_cdecl("utatane_module_bridge") public func misakaBridgeVersion() -> UInt32 {
    1
}
