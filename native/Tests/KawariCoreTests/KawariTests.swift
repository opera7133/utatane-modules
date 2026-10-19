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
    let response = try session.request(request)
    #expect(response.value?.contains("起動") == true, Comment(rawValue: response.serialized()))
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

@Test func unicodeDictionaryRegexAndLambda() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "華和梨😀-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dictionary = #"""
    System.Callback.OnGET: ${event.${System.Request.ID}}
    event.OnBoot: \0日本語😀\e
    event.OnRegex: $(regex_replace "あ1い2" "[0-9]" "X")
    event.OnLambda: $(set f $(lambda $(echo [$@arg[1]])))$(${f} hi)
    """#
    try Data(([0xef, 0xbb, 0xbf] as [UInt8]) + Array(dictionary.utf8))
        .write(to: root.appending(path: "kawarirc.kis"))
    let session = try KawariSession(masterDirectoryURL: root)
    for (event, expected) in [("OnBoot", "日本語😀"), ("OnRegex", "あXいX"), ("OnLambda", "[hi]")] {
        let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: event)]))
        let response = try session.request(request)
        #expect(response.value?.contains(expected) == true, Comment(rawValue: response.serialized()))
    }
}
