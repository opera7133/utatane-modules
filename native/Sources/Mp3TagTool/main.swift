import AudioToolbox
import AVFoundation
import Foundation

// SAORI BASIC compatible, independent read-only metadata helper. No audio output.
do {
    guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
    let url = URL(fileURLWithPath: CommandLine.arguments[1].replacingOccurrences(of: "\\", with: "/"))
    var fileID: AudioFileID?
    guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr, let fileID else {
        throw CocoaError(.fileReadCorruptFile)
    }
    defer { AudioFileClose(fileID) }
    var dictionary: Unmanaged<CFDictionary>?
    var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
    let status = AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &size, &dictionary)
    let metadata = status == noErr ? (dictionary?.takeRetainedValue() as? [String: Any] ?? [:]) : [:]
    let audio = try AVAudioFile(forReading: url)
    let milliseconds = Int64((Double(audio.length) / audio.fileFormat.sampleRate * 1000).rounded())
    func value(_ key: String) -> String { (metadata[key] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown" }
    let fields: [(String, String)] = [
        ("Title", value(kAFInfoDictionary_Title)), ("Artist", value(kAFInfoDictionary_Artist)),
        ("Album", value(kAFInfoDictionary_Album)), ("Year", value(kAFInfoDictionary_Year)),
        ("Genre", value(kAFInfoDictionary_Genre)),
        ("Time", String(format: "%lld:%02lld", milliseconds / 60000, milliseconds / 1000 % 60)),
        ("Milliseconds", String(milliseconds))
    ]
    let text = fields.map { key, value in
        key + ":" + value.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }.joined(separator: "|") + "|"
    FileHandle.standardOutput.write(Data(text.utf8))
} catch {
    FileHandle.standardError.write(Data("mp3tag: \(error.localizedDescription)\n".utf8))
    exit(1)
}
