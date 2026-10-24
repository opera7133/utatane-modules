import AppKit
import Darwin
import Foundation

public struct SaoriExecution {
    public let status: Int
    public let values: [String]
    init(_ status: Int, _ values: [String] = []) { self.status = status; self.values = values }
}

/// Clipboard variants have different argument contracts; they are not aliases.
final class NativeClipboardCompatibility: NativeSaoriModule {
    let clipcopy: Bool
    let handler: (@Sendable (String) -> Void)?
    init(clipcopy: Bool, handler: (@Sendable (String) -> Void)?) { self.clipcopy = clipcopy; self.handler = handler }
    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let first = arguments.first, clipcopy || !first.isEmpty else { return .init(400) }
        let text: String
        if clipcopy {
            text = arguments.joined(separator: "\r\n").replacingOccurrences(of: #"\n"#, with: "\r\n")
        } else if arguments.count >= 3, !arguments[2].isEmpty {
            text = first.replacingOccurrences(of: arguments[2], with: "\r\n")
        } else { text = first }
        if let handler { handler(text) }
        else {
            let copy = { @MainActor in
                let board = NSPasteboard.general
                board.clearContents(); return board.setString(text, forType: .string)
            }
            let success = Thread.isMainThread ? MainActor.assumeIsolated(copy)
                : DispatchQueue.main.sync { MainActor.assumeIsolated(copy) }
            guard success else { return .init(500) }
        }
        if clipcopy { return .init(200) }
        let returnsText = arguments.count >= 2 && arguments[1].withCString { strtoull($0, nil, 10) != 0 }
        return returnsText ? .init(200, [first]) : .init(204)
    }
    func call(_ arguments: [String]) -> String { execute(arguments).values.first ?? "" }
    func unload() {}
}

final class NativeIPCompatibility: NativeSaoriModule {
    let hostname: () -> String?
    let addresses: () -> [String]
    init(hostname: @escaping () -> String? = NativeIPCompatibility.localHostname,
         addresses: @escaping () -> [String] = NativeIPCompatibility.localAddresses) {
        self.hostname = hostname; self.addresses = addresses
    }
    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let command = arguments.first?.lowercased() else { return .init(400) }
        let result: String?
        switch command {
        case "getlocalhostname": result = hostname()
        case "getlocalip": result = addresses().first
        case "getinternetip": return .init(501) // The original uses an external HTTP service; no equivalent is configured.
        default: return .init(400)
        }
        guard let result, !result.isEmpty else { return .init(500) }
        return .init(200, [result])
    }
    func call(_ arguments: [String]) -> String { execute(arguments).values.first ?? "" }
    func unload() {}
    static func localHostname() -> String? {
        var bytes = [CChar](repeating: 0, count: 256)
        guard gethostname(&bytes, bytes.count - 1) == 0 else { return nil }
        return String(cString: bytes)
    }
    static func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var values: [(String, String)] = [], cursor = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = item.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = item.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_INET else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            values.append((String(cString: item.pointee.ifa_name), String(cString: buffer)))
        }
        return values.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
