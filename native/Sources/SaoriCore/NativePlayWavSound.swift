import AVFoundation
import Foundation

protocol WaveSoundPlayback: AnyObject {
    func play(_ url: URL) -> Bool
    func stop()
}

private final class SystemWaveSoundPlayback: WaveSoundPlayback {
    private var player: AVAudioPlayer?
    func play(_ url: URL) -> Bool {
        stop()
        guard let next = try? AVAudioPlayer(contentsOf: url) else { return false }
        next.numberOfLoops = 0
        guard next.prepareToPlay(), next.play() else { return false }
        player = next
        return true
    }
    func stop() { player?.stop(); player = nil }
}

/// Asynchronous, single-sound playback. Windows system aliases use macOS sounds.
final class NativePlayWavSound: NativeSaoriModule {
    private let directory: URL
    private let playback: any WaveSoundPlayback
    private let environment: [String: String]
    private static let systemSounds = [
        "systemasterisk": "Glass", "systemdefault": "Funk", "systemexclamation": "Basso",
        "systemhand": "Basso", "systemquestion": "Pop",
    ]

    init(directory: URL, playback: (any WaveSoundPlayback)? = nil,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.directory = directory
        self.playback = playback ?? SystemWaveSoundPlayback()
        self.environment = environment
    }

    func execute(_ arguments: [String]) -> SaoriExecution {
        guard let path = arguments.first else { return .init(400) }
        if path.lowercased() == "hwnd" { return .init(204) }
        let url: URL
        if path.lowercased().hasPrefix("system:") {
            guard let name = Self.systemSounds[String(path.dropFirst(7)).lowercased()] else { return .init(200, ["0"]) }
            url = URL(filePath: "/System/Library/Sounds/\(name).aiff")
        } else {
            guard !path.isEmpty else { return .init(200, ["0"]) }
            var expanded = path
            if let expression = try? NSRegularExpression(pattern: "%([^%]+)%") {
                for match in expression.matches(in: path, range: NSRange(path.startIndex..., in: path)).reversed() {
                    guard let keyRange = Range(match.range(at: 1), in: path),
                          let wholeRange = Range(match.range, in: expanded),
                          let value = environment[String(path[keyRange])] else { continue }
                    expanded.replaceSubrange(wholeRange, with: value)
                }
            }
            expanded = expanded.replacingOccurrences(of: "\\", with: "/")
            url = expanded.hasPrefix("/") ? URL(filePath: expanded).standardizedFileURL
                : directory.appending(path: expanded).standardizedFileURL
            // Check a bounded header, rather than reading an entire sound into memory.
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  size.isRegularFile == true, let bytes = size.fileSize, bytes >= 12, bytes <= 64 * 1024 * 1024,
                  let file = try? FileHandle(forReadingFrom: url) else { return .init(200, ["0"]) }
            defer { try? file.close() }
            guard let header = try? file.read(upToCount: 12), header.count == 12,
                  header.prefix(4) == Data("RIFF".utf8), header.suffix(4) == Data("WAVE".utf8) else { return .init(200, ["0"]) }
        }
        return .init(200, [playback.play(url) ? "1" : "0"])
    }

    func call(_ arguments: [String]) -> String { execute(arguments).values.first ?? "" }
    func unload() { playback.stop() }
}
