import Foundation
import Testing
@testable import SaoriCore

@Test func proxyExKeepsUnicodeArgumentsAndReplacesNewlines() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "proxy 日本語 \(UUID())")
    let tools = root.appending(path: "bin")
    try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let helper = tools.appending(path: "echoarg")
    try Data("#!/bin/sh\nprintf '%s\\r\\n' \"$@\"\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let proxy = NativeProxyEx(baseDirectoryURL: root, toolsDirectoryURL: tools)
    #expect(proxy.call(["echoarg.exe", "日本語 [2017]", "$(touch nope)"]) == "日本語 [2017] $(touch nope) ")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "nope").path))
    #expect(proxy.call(["/delim", "|"]).isEmpty)
    #expect(proxy.call(["echoarg.exe", "一行目", "二行目"]) == "一行目|二行目|")
    #expect(proxy.call(["missing.exe"]).isEmpty)
    // A PE at the declared location must not hide its native replacement.
    try Data([0x4D, 0x5A]).write(to: root.appending(path: "echoarg.exe"))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "echoarg.exe").path)
    #expect(proxy.call(["echoarg.exe", "日本語"]) == "日本語|")
}
