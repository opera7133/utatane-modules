import Darwin
import Foundation

/// Resolve only a private symbol supplied by the conventional Utatane host.
/// The call happens on the requesting SHIORI thread; workers run in the parent.
enum HttpcHostBridge {
    private typealias Call = @convention(c) (UnsafeRawPointer?, Int32, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?

    static func submit(directory: URL, arguments: [String]) -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "utatane_host_saori_request"),
              arguments.count < 256,
              ([directory.path] + arguments).allSatisfy({ !$0.utf8.contains(13) && !$0.utf8.contains(10) && !$0.utf8.contains(0) }) else { return false }
        let wire = (["EXECUTE SAORI/1.0", "Charset: UTF-8", "Module: utatane_httpc", "Directory: \(directory.path)"]
                    + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
        let bytes = Data(wire.utf8)
        guard bytes.count <= 8 * 1024 * 1024 else { return false }
        let call = unsafeBitCast(symbol, to: Call.self)
        var length: Int32 = 0
        let response = bytes.withUnsafeBytes { call($0.baseAddress, Int32($0.count), &length) }
        guard let response else { return false }
        defer { free(response) }
        guard length > 0, length <= 8 * 1024 * 1024 else { return false }
        return String(decoding: Data(bytes: response, count: Int(length)).prefix(16), as: UTF8.self).hasPrefix("SAORI/1.0 204")
    }
}
