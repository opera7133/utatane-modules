import Foundation
import ModuleProtocol
import Testing
@testable import HisuiCore

@Test func `loads TLK and answers SHIORI requests`() throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let dictionary = master.appending(path: "hisui_base")
    try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    try "sakura.name,翡翠\nkero.name,相方\n".write(
        to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8
    )
    try """
    {
    token:OnBoot
    script:\\0起動\\e
    }
    {
    token:OnHisuiFreeTalk
    script:\\0会話\\e
    }
    {
    token:OnEcho
    script:%ref0
    }
    """.write(to: dictionary.appending(path: "fixture.tlk"), atomically: true, encoding: .utf8)
    let state = master.appending(path: "saved/state.json")
    let engine = try HisuiSession(masterDirectoryURL: master, stateStoreURL: state)
    #expect(try engine.request(request("OnBoot")).value == "\\0起動\\e")
    #expect(try engine.request(request("OnAITalk")).value == "\\0会話\\e")
    #expect(try engine.request(request("OnEcho", reference0: "あ")).value == "あ")
    #expect(FileManager.default.fileExists(atPath: state.path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["HISUI_TEST_MASTER"] != nil))
func `loads an installed Hisui ghost dictionary`() throws {
    let path = try #require(ProcessInfo.processInfo.environment["HISUI_TEST_MASTER"])
    let master = URL(fileURLWithPath: path)
    let state = FileManager.default.temporaryDirectory.appending(path: "hisui-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let engine = try HisuiSession(masterDirectoryURL: master, stateStoreURL: state)
    let boot = try engine.request(request("OnBoot")).value
    #expect(boot?.isEmpty == false)
    #expect(boot?.contains("\\s[") == true)
    #expect(try engine.request(request("OnAITalk")).value?.isEmpty == false)
}

private func request(_ id: String, reference0: String? = nil) -> ShioriRequest {
    var headers = ShioriHeaders([.init(name: "ID", value: id)])
    if let reference0 { headers.append(name: "Reference0", value: reference0) }
    return ShioriRequest(method: "GET", headers: headers)
}
