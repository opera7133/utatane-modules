import AppKit
import AVFoundation
import Foundation

public struct NativeSaoriWindowFrame: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public protocol NativeSaoriWindowControlling: Sendable {
    func frame(scope: Int) -> NativeSaoriWindowFrame?
    func desktopSize() -> (width: Int, height: Int)
    func move(scope: Int, x: Int, speed: Int)
}

protocol NativeSaoriModule: AnyObject {
    func call(_ arguments: [String]) -> String
    func unload()
}

final class NativeSystemInfo: NativeSaoriModule {
    func call(_ arguments: [String]) -> String {
        guard let command = arguments.first else { return "" }
        let processInfo = ProcessInfo.processInfo
        switch command {
        case "os.name", "platform": return "macOS"
        case "os.version": return processInfo.operatingSystemVersionString
        case "os.build": return processInfo.operatingSystemVersionString
        case "cpu.vender": return "Apple"
        case "cpu.name", "cpu.ptype": return machineName()
        case "cpu.clock", "cpu.clockex": return "0"
        case "cpu.num": return String(processInfo.activeProcessorCount)
        case "cpu.family", "cpu.model", "cpu.stepping": return "0"
        case "cpu.mmx", "cpu.mmx+", "cpu.tdn": return "0"
        case "cpu.sse", "cpu.sse2": return machineName() == "x86_64" ? "1" : "0"
        case "cpu.htt": return processInfo.processorCount > processInfo.activeProcessorCount ? "1" : "0"
        case "mem.os": return "0"
        case "mem.phyt", "mem.pagt", "mem.virt":
            return String(processInfo.physicalMemory / 1_048_576)
        case "mem.phya", "mem.paga", "mem.vira":
            return String(processInfo.physicalMemory / 1_048_576)
        default: return ""
        }
    }

    func unload() {}

    private func machineName() -> String {
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }
}

final class NativeKeyword: NativeSaoriModule {
    private struct Entry {
        var keyword: String
        var expressions: [String]
    }

    private var entries: [Entry] = []

    init(moduleURL: URL) {
        let keywordURL = moduleURL.deletingLastPathComponent().appending(path: "keyword.txt")
        guard let data = try? Data(contentsOf: keywordURL),
              let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
        else { return }
        entries = source.components(separatedBy: .newlines).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"),
                  let separator = line.range(of: "＝")
            else { return nil }
            let keyword = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let expressions = line[separator.upperBound...].split(separator: "、").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            guard !keyword.isEmpty, !expressions.isEmpty else { return nil }
            return Entry(keyword: keyword, expressions: expressions)
        }
    }

    func call(_ arguments: [String]) -> String {
        guard arguments.count >= 2, arguments[0] == "GETKEYWORD" else { return "" }
        let source = arguments[1]
        let matches = entries.compactMap { entry -> (keyword: String, offset: Int, length: Int)? in
            let candidates = entry.expressions.compactMap { expression -> (Int, Int)? in
                guard let range = source.range(of: expression) else { return nil }
                return (source.distance(from: source.startIndex, to: range.lowerBound), expression.count)
            }
            guard let best = candidates.min(by: { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 > rhs.1 : lhs.0 < rhs.0
            }) else { return nil }
            return (entry.keyword, best.0, best.1)
        }.sorted { lhs, rhs in
            lhs.offset == rhs.offset ? lhs.length > rhs.length : lhs.offset < rhs.offset
        }
        var keywords: [String] = []
        for match in matches where !keywords.contains(match.keyword) {
            keywords.append(match.keyword)
        }
        return keywords.joined(separator: "\u{1}")
    }

    func unload() {
        entries.removeAll()
    }
}

final class NativeTextCopy: NativeSaoriModule {
    private let pasteboardName: String?
    private let handler: (@Sendable (String) -> Void)?

    init(pasteboardName: String?, handler: (@Sendable (String) -> Void)?) {
        self.pasteboardName = pasteboardName
        self.handler = handler
    }

    func call(_ arguments: [String]) -> String {
        guard let text = arguments.first else { return "" }
        if let handler {
            handler(text)
            return arguments.dropFirst().first == "1" ? text : ""
        }
        let pasteboardName = pasteboardName
        let operation = { @MainActor in
            let pasteboard = pasteboardName.map { NSPasteboard(name: .init($0)) } ?? .general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated(operation) }
        }
        return arguments.dropFirst().first == "1" ? text : ""
    }

    func unload() {}
}

final class NativeMciAudioR: NativeSaoriModule {
    private let baseDirectoryURL: URL
    private var audioURL: URL?
    private var player: AVAudioPlayer?
    private var loops = false

    init(baseDirectoryURL: URL) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func call(_ arguments: [String]) -> String {
        if arguments.count == 2, arguments[0] == "load" {
            stop(); audioURL = resolvedURL(arguments[1])
        } else if arguments == ["stop"] {
            stop()
        } else if arguments == ["loop"] {
            loops = true; togglePlayback()
        } else if arguments == ["play"] {
            togglePlayback()
        }
        return ""
    }

    func unload() {
        stop(); audioURL = nil
    }

    private func togglePlayback() {
        if let player {
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
            return
        }
        guard let audioURL, FileManager.default.fileExists(atPath: audioURL.path),
              let player = try? AVAudioPlayer(contentsOf: audioURL) else { return }
        player.numberOfLoops = loops ? -1 : 0
        player.prepareToPlay(); player.play(); self.player = player
    }

    private func stop() {
        player?.stop(); player = nil
    }

    private func resolvedURL(_ path: String) -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("/") ? URL(filePath: normalized).standardizedFileURL
            : baseDirectoryURL.appending(path: normalized).standardizedFileURL
    }
}

final class NativeWmove: NativeSaoriModule {
    private let windowController: (any NativeSaoriWindowControlling)?

    init(windowController: (any NativeSaoriWindowControlling)?) {
        self.windowController = windowController
    }

    func call(_ arguments: [String]) -> String {
        guard let command = arguments.first?.uppercased() else { return "" }
        switch command {
        case "GET_POSITION":
            guard arguments.count == 2, let scope = scope(arguments[1]),
                  let frame = windowController?.frame(scope: scope) else { return "" }
            return [frame.x, frame.x + frame.width / 2, frame.x + frame.width]
                .map(String.init).joined(separator: "\u{1}")
        case "GET_DESKTOP_SIZE":
            guard arguments.count == 1, let size = windowController?.desktopSize() else { return "" }
            return "\(size.width)\u{1}\(size.height)"
        case "MOVETO", "MOVETO_INSIDE":
            guard arguments.count == 4, let scope = scope(arguments[1]),
                  let x = Int(arguments[2]), let speed = Int(arguments[3]) else { return "" }
            windowController?.move(scope: scope, x: x, speed: max(speed, 0)); return ""
        default: return ""
        }
    }

    func unload() {}

    private func scope(_ identifier: String) -> Int? {
        switch identifier.lowercased() {
        case "0", "sakura": 0
        case "1", "kero": 1
        default: Int(identifier)
        }
    }
}
