import Darwin
import Foundation

/// Metadata is sent on the requesting thread, never from a background worker.
enum SaoriDiagnosticHook {
    private typealias Reporter = @convention(c) (Int32, Int32, UInt64, UInt64, UnsafePointer<CChar>?) -> Void
    static func report(_ phase: Int32, status: Int32, started: UInt64, bytes: Int = 0, path: URL) {
        guard let handle = dlopen(nil, RTLD_NOW) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "utatane_host_saori_diagnostic") else { return }
        let callback = unsafeBitCast(symbol, to: Reporter.self)
        path.path.withCString { callback(phase, status, (DispatchTime.now().uptimeNanoseconds &- started) / 1000, UInt64(max(bytes, 0)), $0) }
    }
    static func status(_ bytes: Data) -> Int32 {
        Int32(String(decoding: bytes.prefix(16), as: UTF8.self).split(separator: " ").dropFirst().first ?? "") ?? 0
    }
}
