import Foundation
import ModuleProtocol
import Testing
@testable import ShinoCore

@Test func `loads Shino dictionary and answers SHIORI requests`() throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    try "sakura.name,Test\nkero.name,Kero\n".write(to: master.appending(path: "descript.txt"),
                                               atomically: true, encoding: .utf8)
    try "\\ev[OnBoot],\\0起動\\e\n".write(to: master.appending(path: "ai_test.txt"),
                                        atomically: true, encoding: .utf8)
    let session = try ShinoSession(masterDirectoryURL: master)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect(try session.request(request).value == "\\0起動\\e")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SHINO_TEST_SAORI"] != nil))
func `calls a conventional SAORI dylib`() throws {
    let source = try #require(ProcessInfo.processInfo.environment["SHINO_TEST_SAORI"])
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    try FileManager.default.copyItem(at: URL(fileURLWithPath: source),
                                     to: master.appending(path: "libsaori_cpuid.dylib"))
    try "sakura.name,Test\n".write(to: master.appending(path: "descript.txt"),
                                     atomically: true, encoding: .utf8)
    try "\\ev[OnBoot],%saori[saori_cpuid.dll,os.name]|%saoriresult[0]\n".write(
        to: master.appending(path: "ai_test.txt"), atomically: true, encoding: .utf8
    )
    let session = try ShinoSession(masterDirectoryURL: master)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect(try session.request(request).value == "macOS|macOS")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SHINO_TEST_MASTER"] != nil))
func `loads an installed Shino ghost dictionary`() throws {
    let path = try #require(ProcessInfo.processInfo.environment["SHINO_TEST_MASTER"])
    let master = URL(fileURLWithPath: path)
    let state = FileManager.default.temporaryDirectory.appending(path: "shino-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let session = try ShinoSession(masterDirectoryURL: master, stateStoreURL: state)
    #expect(session.loadedDictionaryFileCount >= 10)
    #expect(session.loadedEventEntryCount > 20)
    let firstBoot = ShioriRequest(method: "GET", headers: .init([
        .init(name: "ID", value: "OnFirstBoot"), .init(name: "Reference0", value: "0")
    ]))
    #expect(try session.request(firstBoot).value?.contains("ここはどこ") == true)
    #expect(try session.request(ShioriRequest(method: "GET", headers: .init([
        .init(name: "ID", value: "OnAITalk")
    ]))).value?.contains("\\e") == true)
}
