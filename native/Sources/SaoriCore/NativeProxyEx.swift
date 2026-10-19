import Darwin
import Foundation

/// Independent implementation of the proxy_ex SAORI BASIC bridge.
/// Helpers are native programs; the original Windows PE binaries are not executed.
final class NativeProxyEx: NativeSaoriModule {
    private let baseDirectoryURL: URL
    private let toolsDirectoryURL: URL?
    private var delimiter = " "
    private var charset: String.Encoding = .utf8

    init(baseDirectoryURL: URL, toolsDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
        var info = Dl_info()
        if let toolsDirectoryURL {
            self.toolsDirectoryURL = toolsDirectoryURL
        } else if dladdr(#dsohandle, &info) != 0, let path = info.dli_fname {
            self.toolsDirectoryURL = URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "bin")
        } else {
            self.toolsDirectoryURL = nil
        }
    }

    func call(_ arguments: [String]) -> String {
        guard let command = arguments.first else { return "" }
        switch command {
        case "hwnd": return ""
        case "/delim":
            if arguments.count > 1 { delimiter = arguments[1] }
            return ""
        case "/charset":
            switch arguments.dropFirst().first?.lowercased() ?? "" {
            case "shift_jis", "shift-jis", "cp932": charset = .shiftJIS
            case "euc-jp": charset = .japaneseEUC
            case "iso-2022-jp": charset = .iso2022JP
            default: charset = .utf8
            }
            return ""
        default: break
        }
        guard let executable = executableURL(command) else { return "" }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.arguments = Array(arguments.dropFirst())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        // Poll in this request's lifetime. No callback into a dylib may remain
        // scheduled after unload/dlclose.
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var data = Data()
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return ""
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(100, remaining * 1000 + 1)))
            if ready < 0 {
                if errno == EINTR { continue }
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return ""
            }
            guard ready > 0 else { continue }
            guard let chunk = try? output.fileHandleForReading.read(upToCount: 16384), !chunk.isEmpty else { break }
            guard data.count + chunk.count <= 1024 * 1024 else {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                return ""
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let result = String(data: data, encoding: charset) else { return "" }
        return result.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: delimiter)
    }

    private func executableURL(_ command: String) -> URL? {
        let normalized = command.replacingOccurrences(of: "\\", with: "/")
        let relative = URL(fileURLWithPath: normalized, relativeTo: baseDirectoryURL).standardizedFileURL
        var candidates = [relative, baseDirectoryURL.appending(path: "saori").appending(path: normalized)]
        // The managed package supplies compatible native replacements by basename.
        if let toolsDirectoryURL, !normalized.contains("/"), normalized != ".", normalized != ".." {
            let name = normalized.lowercased().hasSuffix(".exe") ? String(normalized.dropLast(4)) : normalized
            candidates.append(toolsDirectoryURL.appending(path: name))
        }
        return candidates.first { url in
            guard FileManager.default.isExecutableFile(atPath: url.path),
                  let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 2)) != Data([0x4D, 0x5A])
        }
    }

    func unload() {}
}
