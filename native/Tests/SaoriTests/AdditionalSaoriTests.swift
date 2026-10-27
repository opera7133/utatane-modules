import Foundation
import Testing
@testable import SaoriCore

// RFC 6238 Appendix B, SHA-1. These are public test keys, never account credentials.
private let rfcKey = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

@Test(arguments: [("59", "94287082"), ("1111111109", "07081804"), ("1111111111", "14050471"),
                  ("1234567890", "89005924"), ("2000000000", "69279037"), ("20000000000", "65353130")])
func totpMatchesRFC6238(time: String, expected: String) {
    let result = NativeTOTP().execute(["totp", rfcKey, time, "8", "30"])
    #expect(result.status == 200)
    #expect(result.values == [expected])
}

@Test func totpDefaultsBase32AndCustomInterval() {
    let totp = NativeTOTP(now: { 59 })
    #expect(totp.execute(["totp", rfcKey]).values == ["287082"])
    #expect(totp.execute(["totp", rfcKey.lowercased(), "119", "8", "60"]).values == ["94287082"])
    #expect(totp.execute(["totp", rfcKey, "59", "1"]).values == ["2"])
    #expect(totp.execute(["totp", "MY======", "59"]).values == totp.execute(["totp", "MY", "59"]).values)
    // A trailing zero byte is part of the key, not disposable padding.
    #expect(totp.execute(["totp", "MZXW6AA", "59"]).status == 200)
    #expect(totp.execute(["totp", String(repeating: "A", count: 8193)]).status == 400)
    // Python hashlib/hmac reference: bytes 1...64 followed by zero. Dropping
    // that zero changes HMAC's long-key hashing, unlike a short padded key.
    let longKey = "AEBAGBAFAYDQQCIKBMGA2DQPCAIREEYUCULBOGAZDINRYHI6D4QCCIRDEQSSMJZIFEVCWLBNFYXTAMJSGM2DKNRXHA4TUOZ4HU7D6QAA"
    #expect(totp.execute(["totp", longKey, "59", "8"]).values == ["94502757"])
}

@Test(arguments: [[], ["unknown"], ["totp"], ["totp", ""], ["totp", "A"], ["totp", "MZ"],
                  ["totp", "MY=====X"], ["totp", "MY=============="], ["totp", "A!"], ["totp", "日本語"],
                  ["totp", rfcKey, "-1"], ["totp", rfcKey, "abc"], ["totp", rfcKey, "59", "0"],
                  ["totp", rfcKey, "59", "10"], ["totp", rfcKey, "59", "6", "0"],
                  ["totp", rfcKey, "59", "6", "-1"], ["keygen", "0"], ["keygen", "1025"], ["keygen", "x"]])
func totpRejectsMalformedParameters(arguments: [String]) {
    #expect(NativeTOTP().execute(arguments).status == 400)
}

@Test(arguments: [1, 2, 5, 30, 32, 1024])
func totpGeneratesUsableBase32Keys(length: Int) throws {
    let totp = NativeTOTP(now: { 59 })
    let generated = totp.execute(["keygen", String(length)])
    #expect(generated.status == 200)
    let key = try #require(generated.values.first)
    #expect(key.count == (length * 8 + 4) / 5)
    #expect(key.allSatisfy { "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) })
    #expect(totp.execute(["totp", key]).status == 200)
    #expect(totp.execute(["keygen"]).values.first?.count == 48)
}

private final class SoundCapture: WaveSoundPlayback {
    var played: [URL] = []
    var stops = 0
    var succeeds = true
    func play(_ url: URL) -> Bool { played.append(url); return succeeds }
    func stop() { stops += 1 }
}

@Test func wavePathsAliasesAndUnloadKeepOriginalResponseContract() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "効果音 \(UUID())")
    try FileManager.default.createDirectory(at: root.appending(path: "音"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "音/テスト.wav")
    try Data("RIFFxxxxWAVE".utf8).write(to: file)
    try Data("invalid sound".utf8).write(to: root.appending(path: "bad.wav"))
    let oversized = root.appending(path: "large.wav")
    try Data("RIFFxxxxWAVE".utf8).write(to: oversized)
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
    try handle.close()
    let playback = SoundCapture()
    let wave = NativePlayWavSound(directory: root, playback: playback, environment: ["WAVE_ROOT": root.path])
    #expect(wave.execute([]).status == 400)
    #expect(wave.execute(["hwnd", "123"]).status == 204)
    #expect(playback.played.isEmpty)
    for path in [#"音\テスト.wav"#, file.path, #"%WAVE_ROOT%\音\テスト.wav"#] {
        #expect(wave.execute([path]).values == ["1"])
        #expect(playback.played.last == file)
    }
    let count = playback.played.count
    for path in ["", "missing.wav", "bad.wav", "large.wav", "system:unknown", "system:../Glass"] {
        #expect(wave.execute([path]).values == ["0"])
    }
    #expect(playback.played.count == count)
    #expect(wave.execute(["SYSTEM:SystemExclamation"]).values == ["1"])
    #expect(playback.played.last?.path == "/System/Library/Sounds/Basso.aiff")
    playback.succeeds = false
    #expect(wave.execute([file.path]).values == ["0"])
    wave.unload()
    #expect(playback.stops == 1)
    // The real decoder must reject a fake RIFF header before any playback starts.
    #expect(NativePlayWavSound(directory: root).execute([file.path]).values == ["0"])
}
