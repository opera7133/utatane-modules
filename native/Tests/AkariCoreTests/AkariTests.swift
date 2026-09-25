import Foundation
import ModuleProtocol
import Testing
@testable import AkariCore

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
