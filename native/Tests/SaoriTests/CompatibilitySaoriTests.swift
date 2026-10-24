import Foundation
import Testing
@testable import SaoriCore

private final class ClipboardCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var contents: String?
    var value: String? { lock.withLock { contents } }
    func set(_ value: String) { lock.withLock { contents = value } }
}

@Test func clipboardVariantsKeepTheirDistinctContracts() {
    let capture = ClipboardCapture()
    let clip = NativeClipboardCompatibility(clipcopy: true, handler: capture.set)
    #expect(clip.execute([]).status == 400)
    #expect(capture.value == nil)
    #expect(clip.execute([#"日本語\n次"#, "最後"]).status == 200)
    #expect(capture.value == "日本語\r\n次\r\n最後")
    #expect(clip.execute([""]).status == 200)
    #expect(capture.value == "")
    let text = NativeClipboardCompatibility(clipcopy: false, handler: capture.set)
    #expect(text.execute([""]).status == 400)
    let reply = text.execute(["one|日本語|three", "2suffix", "|"])
    #expect(reply.status == 200)
    #expect(reply.values == ["one|日本語|three"])
    #expect(capture.value == "one\r\n日本語\r\nthree")
    #expect(text.execute(["unchanged", "0", ""]).status == 204)
    #expect(capture.value == "unchanged")
}

@Test func ipCommandsDistinguishUnavailableDataAndUnsupportedInternetLookup() {
    let ip = NativeIPCompatibility(hostname: { "probe.local" }, addresses: { ["192.0.2.3", "192.0.2.4"] })
    #expect(ip.execute(["GetLocalHostname"]).values == ["probe.local"])
    #expect(ip.execute(["getlocalip"]).values == ["192.0.2.3"])
    #expect(ip.execute(["GetInternetIP"]).status == 501)
    #expect(ip.execute(["unknown"]).status == 400)
    #expect(ip.execute([]).status == 400)
    #expect(NativeIPCompatibility(hostname: { nil }, addresses: { [] }).execute(["GetLocalIP"]).status == 500)
}
