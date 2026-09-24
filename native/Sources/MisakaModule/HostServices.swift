import CMisakaHostBridge
import Foundation
import MisakaCore

final class HostServices: NativeSaoriCalling, @unchecked Sendable {
    let host: UMHostV1?
    // Access is serialized by the owning session's lock.
    var failure: String?
    init(_ host: UMHostV1?) {
        self.host = host
    }

    func load(_ path: String) {
        _ = invoke(1, path, [])
    }

    func unload(_ path: String) {
        _ = invoke(2, path, [])
    }

    func call(_ path: String, arguments: [String]) -> String {
        invoke(3, path, arguments)
    }

    private func invoke(_ operation: UInt32, _ path: String, _ arguments: [String]) -> String {
        guard let host, let call = host.saori, let release = host.release else {
            failure = failure ?? "SAORI host service is unavailable: \(path)"
            return ""
        }
        let strings = [path] + arguments
        guard strings.allSatisfy({ $0.utf8.count <= UM_MAX_BYTES && !$0.contains("\0") }),
              arguments.count <= Int(UInt32.max)
        else {
            failure = failure ?? "SAORI arguments exceed the API limits"
            return ""
        }
        let pointers = strings.map { value -> UnsafeMutablePointer<UInt8> in
            let bytes = Array(value.utf8)
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
            pointer.initialize(from: bytes, count: bytes.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }
        let spans = zip(strings, pointers).map { UMBytes(data: UnsafePointer($0.1), length: UInt32($0.0.utf8.count)) }
        var result = UMBuffer()
        let status = Array(spans.dropFirst()).withUnsafeBufferPointer {
            call(host.context, operation, spans[0], $0.baseAddress, UInt32($0.count), &result)
        }
        defer {
            if result.data != nil {
                release(host.context, &result)
            }
        }
        guard status == 0, result.length <= UM_MAX_BYTES,
              result.length == 0 || result.data != nil
        else {
            failure = failure ?? "SAORI host callback failed: \(path) (status \(status))"
            return ""
        }
        guard result.length > 0 else { return "" }
        guard let text = String(bytes: UnsafeBufferPointer(start: result.data, count: Int(result.length)), encoding: .utf8),
              !text.contains("\0")
        else {
            failure = failure ?? "SAORI host returned invalid UTF-8"
            return ""
        }
        return text
    }
}
