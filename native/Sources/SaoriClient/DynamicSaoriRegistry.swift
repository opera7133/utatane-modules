import Darwin
import Foundation
import LegacyText

public protocol SaoriCalling: AnyObject, Sendable {
    func load(_ path: String)
    func unload(_ path: String)
    func call(_ path: String, arguments: [String]) -> String
}

/// Loads conventional SAORI dylibs next to the ghost or under a baseware-supplied catalog root.
public final class DynamicSaoriRegistry: SaoriCalling, @unchecked Sendable {
    private typealias Load = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias Request = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
    private typealias Unload = @convention(c) () -> Int32

    private final class Module {
        let handle: UnsafeMutableRawPointer
        let request: Request
        let unload: Unload

        init?(url: URL, directory: URL) {
            guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { return nil }
            guard let loadSymbol = dlsym(handle, "loadu") ?? dlsym(handle, "load"),
                  let requestSymbol = dlsym(handle, "request"),
                  let unloadSymbol = dlsym(handle, "unload")
            else { dlclose(handle); return nil }
            let load = unsafeBitCast(loadSymbol, to: Load.self)
            let path = Array(directory.path.utf8)
            guard path.count <= Int32.max, let buffer = malloc(path.count) else {
                dlclose(handle)
                return nil
            }
            path.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { buffer.copyMemory(from: base, byteCount: bytes.count) }
            }
            guard load(buffer, Int32(path.count)) == 1 else {
                dlclose(handle)
                return nil
            }
            self.handle = handle
            request = unsafeBitCast(requestSymbol, to: Request.self)
            unload = unsafeBitCast(unloadSymbol, to: Unload.self)
        }

        deinit {
            _ = unload()
            dlclose(handle)
        }

        func call(_ arguments: [String]) -> String {
            let lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8"]
                + arguments.enumerated().map { "Argument\($0.offset): \($0.element.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))" }
            let wire = lines.joined(separator: "\r\n") + "\r\n\r\n"
            let input = Array(wire.utf8)
            guard input.count <= Int32.max, let buffer = malloc(input.count) else { return "" }
            input.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { buffer.copyMemory(from: base, byteCount: bytes.count) }
            }
            var length = Int32(input.count)
            guard let output = request(buffer, &length) else { return "" }
            defer { free(output) }
            guard length > 0, length <= 8 * 1024 * 1024 else { return "" }
            let data = Data(bytes: output, count: Int(length))
            guard let response = LegacyTextDecoder.decode(data, preferredCharset: "UTF-8"),
                  response.hasPrefix("SAORI/1.0 200") else { return "" }
            var result = ""
            var values: [Int: String] = [:]
            for line in response.components(separatedBy: "\r\n") {
                guard let separator = line.firstIndex(of: ":") else { continue }
                let name = line[..<separator].lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                if name == "result" { result = value }
                if name.hasPrefix("value"), let index = Int(name.dropFirst(5)), index < 256 {
                    values[index] = value
                }
            }
            let ordered = (0 ..< (values.keys.max().map { $0 + 1 } ?? 0)).map { values[$0] ?? "" }
            return ([result] + ordered).joined(separator: "\u{1}")
        }

        func response(_ wire: String, charset: String) -> String? {
            guard let data = LegacyTextDecoder.encode(wire, charset: charset),
                  data.count <= Int32.max,
                  let buffer = malloc(max(data.count, 1)) else { return nil }
            data.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { buffer.copyMemory(from: base, byteCount: bytes.count) }
            }
            var length = Int32(data.count)
            guard let output = request(buffer, &length) else { return nil }
            defer { free(output) }
            guard length > 0, length <= 8 * 1024 * 1024 else { return nil }
            return LegacyTextDecoder.decode(Data(bytes: output, count: Int(length)), preferredCharset: charset)
        }
    }

    private let baseDirectoryURL: URL
    private let catalogRootURL: URL?
    private let lock = NSLock()
    private var modules: [String: Module] = [:]

    public init(baseDirectoryURL: URL, catalogRootURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
        self.catalogRootURL = catalogRootURL ?? ProcessInfo.processInfo.environment["SHINO_SAORI_ROOT"].map(URL.init(fileURLWithPath:))
    }

    public func load(_ path: String) {
        lock.withLock { loadUnlocked(path) }
    }

    private func loadUnlocked(_ path: String) {
        let name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        guard name.lowercased().hasSuffix(".dll"), name.count > 4,
              name.dropLast(4).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return }
        let stem = String(name.dropLast(4)).lowercased()
        guard modules[stem] == nil else { return }
        let filenames = ["\(stem).dylib", "lib\(stem).dylib"]
        let directories = [baseDirectoryURL] + (catalogRootURL.map { [$0.appending(path: stem).appending(path: "lib"), $0] } ?? [])
        for directory in directories {
            for filename in filenames {
                let candidate = directory.appending(path: filename)
                if let module = Module(url: candidate, directory: baseDirectoryURL) {
                    modules[stem] = module
                    return
                }
            }
        }
    }

    public func unload(_ path: String) {
        lock.withLock {
            let name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
            let stem = String(name.dropLast(min(name.count, 4))).lowercased()
            modules.removeValue(forKey: stem)
        }
    }

    public func call(_ path: String, arguments: [String]) -> String {
        lock.withLock {
            let name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
            let stem = String(name.dropLast(min(name.count, 4))).lowercased()
            return modules[stem]?.call(arguments) ?? ""
        }
    }

    public func response(path: String, request: String) -> String? {
        lock.withLock {
            loadUnlocked(path)
            let name = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
            let stem = String(name.dropLast(min(name.count, 4))).lowercased()
            let charset = request.lowercased().contains("charset: shift_jis") ? "Shift_JIS" : "UTF-8"
            return modules[stem]?.response(request, charset: charset)
        }
    }
}
