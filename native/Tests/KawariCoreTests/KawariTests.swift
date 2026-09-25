import Foundation
import ModuleProtocol
import Testing
@testable import KawariCore

@Test func legacyDictionaryAnswersBoot() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "kawari-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try #require("dict : events.txt\r\n".data(using: .shiftJIS))
        .write(to: root.appending(path: "kawari.ini"))
    try #require("event.OnBoot : \\0起動\\e\r\n".data(using: .shiftJIS))
        .write(to: root.appending(path: "events.txt"))
    let session = try KawariSession(masterDirectoryURL: root)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect(try session.request(request).value?.contains("起動") == true)
    let notification = ShioriRequest(method: "NOTIFY", headers: .init([
        .init(name: "ID", value: "installedkeroname"),
        .init(name: "Reference0", value: "우뉴")
    ]))
    #expect(try session.request(notification).statusCode == 200)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["KAWARI_TEST_MASTER"] != nil))
func installedGhostDictionaryLoads() throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["KAWARI_TEST_MASTER"]))
    let master = FileManager.default.temporaryDirectory.appending(path: "kawari-ghost-\(UUID())")
    defer { try? FileManager.default.removeItem(at: master) }
    try FileManager.default.copyItem(at: source, to: master)
    let session = try KawariSession(masterDirectoryURL: master)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect((200 ..< 300).contains(try session.request(request).statusCode))
}
