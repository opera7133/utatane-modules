import Foundation
import ModuleProtocol
import Testing
@testable import AkariCore

@Test func pluginWireAndShutdownPersistOnlyOnce() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "akari plugin 日本語 \(UUID())")
    let master = root.appending(path: "plugin")
    let state = root.appending(path: "state/akari-vars.json")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "filename,akari.dll\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    try #"""
    int unloaded;
    load() { unloaded = 0; }
    unload() { unloaded += 1; _vsave("unloads", unloaded); }
    array _customrequest(dict req) {
        array response;
        response += "PLUGIN/2.0 200 OK";
        response += "Charset: UTF-8";
        response += "Script: 日本語";
        response += "";
        return response;
    }
    """#.write(to: master.appending(path: "main.azr"), atomically: true, encoding: .utf8)
    let session = try AkariSession(masterDirectoryURL: master, variableStoreURL: state)
    let request = ShioriRequest(method: "GET", version: "PLUGIN/2.0", headers: .init([.init(name: "ID", value: "OnMenuExec")]))
    let reply = try await session.pluginResponse(for: request)
    #expect(reply.version == "PLUGIN/2.0")
    #expect(reply.headers["Script"] == "日本語")
    try await session.shutdown()
    let saved = root.appending(path: "state/files/variables/unloads.json")
    let before = try Data(contentsOf: saved)
    let value = try JSONDecoder().decode(AkariValue.self, from: before)
    #expect(value.integerValue == 1)
    try await session.shutdown()
    #expect(try Data(contentsOf: saved) == before)
}

@Test func plainEventUsesConventionalShiori() async throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    try "shiori,akari.dll\n".write(to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    try "＊OnBoot\n・（０）こんにちは。\n".write(to: master.appending(path: "akari.txt"), atomically: true, encoding: .utf8)
    #expect(AkariSession.supports(masterDirectoryURL: master))
    let session = try AkariSession(masterDirectoryURL: master)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    let response = try await session.request(request)
    #expect(response.statusCode == 200)
    #expect(response.value?.contains("こんにちは") == true)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AKARI_TEST_MASTER"] != nil))
func installedGhostDictionaryLoads() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["AKARI_TEST_MASTER"])
    let master = URL(fileURLWithPath: path)
    let state = FileManager.default.temporaryDirectory.appending(path: "akari-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let session = try AkariSession(masterDirectoryURL: master, variableStoreURL: state)
    let boot = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect(try await session.request(boot).value?.contains("\\e") == true)
    try await session.shutdown()
    #expect(FileManager.default.fileExists(atPath: state.path))
}
