import Darwin
import Foundation
import SaoriCore

/// Private wmove connection. Operations: 1=frame, 2=desktop size, 3=move.
/// Output has four Int32 slots; the callback returns 1 on success, 0 on failure.
public typealias SaoriWindowCallback = @convention(c) (Int32, Int32, Int32, Int32, UnsafeMutablePointer<Int32>?) -> Int32

private final class WindowConnection: NativeSaoriWindowControlling, @unchecked Sendable {
    let callback: SaoriWindowCallback
    init(_ callback: @escaping SaoriWindowCallback) {
        self.callback = callback
    }

    func frame(scope: Int) -> NativeSaoriWindowFrame? {
        guard let scope = Int32(exactly: scope) else { return nil }
        var output = [Int32](repeating: 0, count: 4)
        guard callback(1, scope, 0, 0, &output) == 1 else { return nil }
        return .init(x: Int(output[0]), y: Int(output[1]), width: Int(output[2]), height: Int(output[3]))
    }

    func desktopSize() -> (width: Int, height: Int) {
        var output = [Int32](repeating: 0, count: 4)
        guard callback(2, 0, 0, 0, &output) == 1 else { return (0, 0) }
        return (Int(output[0]), Int(output[1]))
    }

    func move(scope: Int, x: Int, speed: Int) {
        guard let scope = Int32(exactly: scope), let x = Int32(exactly: x), let speed = Int32(exactly: speed) else { return }
        var output = [Int32](repeating: 0, count: 4)
        _ = callback(3, scope, x, speed, &output)
    }
}

public final class ConventionalSaoriSession: @unchecked Sendable {
    private let lock = NSLock()
    private let kind: SaoriKind
    private let textCopyHandler: (@Sendable (String) -> Void)?
    private var windows: WindowConnection?
    private var engine: SaoriEngine?
    private static let maximumBytes = 8 * 1024 * 1024

    public init(kind: SaoriKind, textCopyHandler: (@Sendable (String) -> Void)? = nil) {
        self.kind = kind
        self.textCopyHandler = textCopyHandler
    }

    public func setWindowCallback(_ callback: SaoriWindowCallback?) -> Int32 {
        guard lock.try() else { return 0 }
        defer { lock.unlock() }
        guard engine == nil else { return 0 }
        windows = callback.map(WindowConnection.init)
        return 1
    }

    public func load(_ input: UnsafeMutableRawPointer?, _ length: Int32) -> Int32 {
        defer { free(input) }
        guard let input, length > 0, length <= Self.maximumBytes,
              let path = String(bytes: UnsafeRawBufferPointer(start: input, count: Int(length)), encoding: .utf8),
              path.hasPrefix("/"), !path.contains("\0") else { return 0 }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { return 0 }
        guard lock.try() else { return 0 }
        defer { lock.unlock() }
        guard engine == nil else { return 0 }
        engine = SaoriEngine(kind: kind, directoryURL: URL(fileURLWithPath: path),
                             windowController: windows, textCopyHandler: textCopyHandler)
        return 1
    }

    public func unload() -> Int32 {
        guard lock.try() else { return 0 }
        defer { lock.unlock() }
        engine = nil
        windows = nil
        return 1
    }

    public func request(_ input: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer? {
        defer { free(input) }
        guard let length else { return nil }
        let count = length.pointee
        length.pointee = 0
        guard let input, count > 0, count <= Self.maximumBytes else { return nil }
        let data = Data(bytes: input, count: Int(count))
        guard !data.contains(0) else { return nil }
        // Charset names are ASCII even when the argument bytes are Shift_JIS.
        let headerLines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
        let charsetHeaders = headerLines.filter { $0.lowercased().hasPrefix("charset:") }
        let charset = charsetHeaders.first?.dropFirst(8).trimmingCharacters(in: .whitespaces).lowercased() ?? "shift_jis"
        let encoding: String.Encoding
        let charsetName: String
        switch charset {
        case "utf-8": encoding = .utf8; charsetName = "UTF-8"
        case "shift_jis", "shift-jis", "cp932": encoding = .shiftJIS; charsetName = "Shift_JIS"
        default: return response(400, charset: "UTF-8", encoding: .utf8, length: length)
        }
        guard charsetHeaders.count <= 1, let wire = String(data: data, encoding: encoding), wire.hasSuffix("\r\n\r\n") else {
            return response(400, charset: charsetName, encoding: encoding, length: length)
        }
        var lines = wire.components(separatedBy: "\r\n")
        let command = lines.removeFirst()
        var arguments: [Int: String] = [:]
        for line in lines.prefix(while: { !$0.isEmpty }) {
            guard let colon = line.firstIndex(of: ":") else {
                return response(400, charset: charsetName, encoding: encoding, length: length)
            }
            let name = line[..<colon].lowercased()
            if name.hasPrefix("argument") {
                guard let index = Int(name.dropFirst(8)), index >= 0, index < 1024, arguments[index] == nil else {
                    return response(400, charset: charsetName, encoding: encoding, length: length)
                }
                var value = String(line[line.index(after: colon)...])
                if value.hasPrefix(" ") {
                    value.removeFirst()
                }
                arguments[index] = value
            }
        }
        guard Set(arguments.keys) == Set(0 ..< arguments.count) else {
            return response(400, charset: charsetName, encoding: encoding, length: length)
        }
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        guard engine != nil else { return response(503, charset: charsetName, encoding: encoding, length: length) }
        if command == "GET Version SAORI/1.0" {
            return response(200, charset: charsetName, encoding: encoding, length: length)
        }
        guard command == "EXECUTE SAORI/1.0" else {
            return response(400, charset: charsetName, encoding: encoding, length: length)
        }
        if kind == .wmove, windows == nil {
            return response(501, charset: charsetName, encoding: encoding, length: length)
        }
        let values = engine!.call((0 ..< arguments.count).map { arguments[$0]! })
        return response(values.allSatisfy(\.isEmpty) ? 204 : 200, values: values,
                        charset: charsetName, encoding: encoding, length: length)
    }

    private func response(_ status: Int, values: [String] = [], charset: String, encoding: String.Encoding,
                          length: UnsafeMutablePointer<Int32>) -> UnsafeMutableRawPointer?
    {
        let reasons = [200: "OK", 204: "No Content", 400: "Bad Request", 501: "Not Implemented", 503: "Service Unavailable"]
        var text = "SAORI/1.0 \(status) \(reasons[status]!)\r\nCharset: \(charset)\r\n"
        if status == 200, let first = values.first {
            func escaped(_ value: String) -> String {
                value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            }
            text += "Result: \(escaped(first))\r\n"
            for (index, value) in values.dropFirst().enumerated() {
                text += "Value\(index): \(escaped(value))\r\n"
            }
        }
        text += "\r\n"
        guard let bytes = text.data(using: encoding), bytes.count <= Self.maximumBytes,
              let output = malloc(max(bytes.count, 1)) else { return nil }
        bytes.copyBytes(to: output.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        length.pointee = Int32(bytes.count)
        return output
    }
}
