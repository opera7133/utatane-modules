import Darwin
import Foundation

/// Portable C# SHIORI runs outside the dylib, one managed process per ghost.
private final class ManagedSession: @unchecked Sendable {
    static let shared = ManagedSession()
    let lock = NSLock()
    var lastError = ""
    var process: Process?
    var input: FileHandle?
    var output: FileHandle?

    func stop() {
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        try? input?.close(); try? output?.close()
        process = nil; input = nil; output = nil
    }
    func read(_ size: Int, deadline: UInt64) throws -> Data {
        guard let output else { throw CocoaError(.fileReadUnknown) }
        var result = Data()
        while result.count < size {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw CocoaError(.fileReadUnknown) }
            let millis = min(UInt64(Int32.max), max(1, (deadline - now) / 1_000_000))
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(millis))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0, descriptor.revents & Int16(POLLIN) != 0,
                  let part = try output.read(upToCount: size - result.count), !part.isEmpty
            else { throw CocoaError(.fileReadUnknown) }
            result.append(part)
        }
        return result
    }
    func packet(seconds: UInt64) throws -> Data {
        let deadline = DispatchTime.now().uptimeNanoseconds + seconds * 1_000_000_000
        let header = try read(4, deadline: deadline)
        let count = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        guard count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try read(Int(count), deadline: deadline)
    }
    func write(_ data: Data) throws {
        guard let input, data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileWriteUnknown) }
        var size = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }; frame.append(data)
        try input.write(contentsOf: frame)
    }
    func start(_ directory: String) throws -> Bool {
        guard process == nil else { return false }
        let environment = ProcessInfo.processInfo.environment
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let image = info.dli_fname else { return false }
        let imageURL = URL(fileURLWithPath: String(cString: image))
        let host = environment["UTATANE_DNPROXY_HOST"].map { URL(fileURLWithPath: $0) }
            ?? imageURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "bin/DnProxyHost.dll")
        let candidates = environment["UTATANE_DOTNET"].map { [$0] }
            ?? (["/usr/local/share/dotnet/dotnet", "/opt/homebrew/bin/dotnet"]
                + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/dotnet" })
        guard let executable = candidates.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }),
              FileManager.default.fileExists(atPath: host.path) else { return false }
        let process = Process(), incoming = Pipe(), outgoing = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [host.path, directory]
        process.environment = environment.merging(["UTATANE_DOTNET": executable]) { _, new in new }
        process.standardInput = incoming; process.standardOutput = outgoing; process.standardError = FileHandle.standardError
        try process.run()
        self.process = process; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        // A managed host may exit before the next write. Do not deliver SIGPIPE to the SHIORI host.
        guard fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { stop(); return false }
        do {
            let status = try packet(seconds: 130)
            guard status == Data([1]) else {
                lastError = status.first == 0 ? String(decoding: status.dropFirst(), as: UTF8.self) : "DNProxy: invalid startup response"
                stop(); return false
            }
            return true
        } catch { stop(); throw error }
    }
}

private func load(_ pointer: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
    defer { free(pointer) }
    guard let pointer, (1 ... 8 * 1024 * 1024).contains(length),
          let directory = String(data: Data(bytes: pointer, count: Int(length)), encoding: .utf8),
          directory.hasPrefix("/"), !directory.contains("\0") else { return 0 }
    let session = ManagedSession.shared
    guard session.lock.try() else { return 0 }; defer { session.lock.unlock() }
    session.lastError = ""
    do {
        if try session.start(directory) { return 1 }
        if session.lastError.isEmpty { session.lastError = "DNProxy: dotnet / host DLL is missing, or initialization failed" }
    } catch { session.lastError = "DNProxy: " + error.localizedDescription }
    return 0
}
@_cdecl("loadu")
public func dnLoadUTF8(_ pointer: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 { load(pointer, length) }
@_cdecl("load")
public func dnLoad(_ pointer: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 { load(pointer, length) }
@_cdecl("unload")
public func dnUnload() -> Int32 {
    let session = ManagedSession.shared
    guard session.lock.try() else { return 0 }; defer { session.lock.unlock() }
    guard session.process != nil else { return 1 }
    defer { session.stop() }
    do { try session.write(Data()); return try session.packet(seconds: 10) == Data([1]) ? 1 : 0 }
    catch { return 0 }
}
@_cdecl("request")
public func dnRequest(_ pointer: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    defer { free(pointer) }
    guard let length else { return nil }
    let size = length.pointee; length.pointee = 0
    guard let pointer, (1 ... 8 * 1024 * 1024).contains(size) else { return nil }
    let data = Data(bytes: pointer, count: Int(size))
    guard let text = String(data: data, encoding: .utf8), !text.contains("\0"), text.hasSuffix("\r\n\r\n") else { return nil }
    let session = ManagedSession.shared
    guard session.lock.try() else { return nil }; defer { session.lock.unlock() }
    guard session.process != nil else { return nil }
    do {
        try session.write(data)
        let response = try session.packet(seconds: 30)
        guard !response.isEmpty, let result = malloc(response.count) else { return nil }
        response.withUnsafeBytes { result.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        length.pointee = Int32(response.count); return result
    } catch { session.stop(); return nil }
}

// The native SHIORI host copies and frees this bounded diagnostic after load fails.
@_cdecl("utatane_shiori_last_error")
public func dnLastError(_ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
    guard let length else { return nil }
    length.pointee = 0
    let session = ManagedSession.shared
    guard session.lock.try() else { return nil }; defer { session.lock.unlock() }
    let bytes = Array(String(String.UnicodeScalarView(session.lastError.unicodeScalars.prefix(900))).utf8)
    guard !bytes.isEmpty, let output = malloc(bytes.count + 1) else { return nil }
    bytes.withUnsafeBytes { if let source = $0.baseAddress { memcpy(output, source, bytes.count) } }
    output.storeBytes(of: UInt8(0), toByteOffset: bytes.count, as: UInt8.self)
    length.pointee = Int32(bytes.count)
    return output
}
