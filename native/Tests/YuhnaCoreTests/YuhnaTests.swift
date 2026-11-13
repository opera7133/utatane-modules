import Foundation
import ModuleProtocol
import Testing
@testable import YuhnaCore

@Test func `loads YDF and answers ordinary conditional and mouse requests`() throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    var data = Data("YDF/1.07 fixture".utf8)
    data.append(contentsOf: [0, 0, 0, 3])
    appendEvent("OnYuhnaRandomTalk", script: "\\0talk\\e", to: &data)
    appendEvent("OnBoot", script: "\\0boot:%ref0\\e", to: &data)
    appendEvent("OnYuhnaMouseDoubleClick0", script: "\\0click\\e", to: &data)
    try data.write(to: master.appending(path: "dic.ydf"))
    let state = master.appending(path: "saved/state.json")
    let engine = try YuhnaSession(masterDirectoryURL: master, stateStoreURL: state)
    #expect(engine.loadedEventCount == 3)
    #expect(try engine.request(request("OnBoot", references: [0: "hello"])).value == "\\0boot:hello\\e")
    #expect(try engine.request(request("OnAITalk")).value == "\\0talk\\e")
    #expect(try engine.request(request("OnMouseDoubleClick", references: [3: "0"])).value == "\\0click\\e")
    #expect(try engine.request(request("OnUnknown")).statusCode == 204)
    try engine.save()
    #expect(FileManager.default.fileExists(atPath: state.path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["YUHNA_TEST_MASTER"] != nil))
func `loads an installed Yuhna ghost dictionary`() throws {
    let path = try #require(ProcessInfo.processInfo.environment["YUHNA_TEST_MASTER"])
    let master = URL(fileURLWithPath: path)
    let state = FileManager.default.temporaryDirectory.appending(path: "yuhna-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let engine = try YuhnaSession(masterDirectoryURL: master, stateStoreURL: state)
    #expect(engine.loadedEventCount >= 40)
    #expect(engine.loadedRuleCount >= 60)
    #expect(engine.conditionalRuleCount >= 20)
    #expect(try engine.request(request("OnBoot")).value?.contains("本日は御日柄も良く") == true)
    #expect(try engine.request(request("OnAITalk")).value != nil)
    #expect(try engine.request(request("OnMouseDoubleClick", references: [3: "0", 4: "Head"])).value?.contains("頭") == true)
}

private func request(_ id: String, references: [Int: String] = [:]) -> ShioriRequest {
    var headers = ShioriHeaders([.init(name: "ID", value: id)])
    for (index, value) in references.sorted(by: { $0.key < $1.key }) {
        headers.append(name: "Reference\(index)", value: value)
    }
    return ShioriRequest(method: "GET", headers: headers)
}

private func appendEvent(_ name: String, script: String, to data: inout Data) {
    let nameBytes = Array(name.utf8)
    let scriptBytes = Array(script.utf8)
    data.append(contentsOf: [UInt8(nameBytes.count >> 8), UInt8(nameBytes.count & 0xFF)])
    data.append(contentsOf: nameBytes)
    data.append(contentsOf: [0, 0, 0, 0, 1])
    data.append(contentsOf: [UInt8(scriptBytes.count >> 8), UInt8(scriptBytes.count & 0xFF), 0])
    data.append(contentsOf: scriptBytes)
}

@Test func yuhnaIntegerExpressionsAndLiteralReferences() throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    var data = Data("YDF/1.07 fixture".utf8)
    data.append(contentsOf: [0, 0, 0, 3])
    appendEvent("OnYuhnaRandomTalk", script: "talk", to: &data)
    appendEvent("OnCompute", script: "{a=2+3*4}{b=(a-4)/3}{c=2/(1-1)}{d=missing+2}{a}:{b}:{c}:{d}:%ref10", to: &data)
    appendEvent("OnRead", script: "{a}", to: &data)
    try data.write(to: master.appending(path: "dic.ydf"))
    let engine = try YuhnaSession(masterDirectoryURL: master)
    let input = "{a=99}$i[0]%ref0"
    #expect(try engine.request(request("OnCompute", references: [1: "wrong", 10: input])).value == "14:3:0:2:" + input)
    let reloaded = try YuhnaSession(masterDirectoryURL: master)
    #expect(try reloaded.request(request("OnRead")).value == "14")
}

@Test func `loads long YDF scripts after a preceding dictionary section`() throws {
    let master = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: master) }
    var data = Data("YDF/1.07 fixture".utf8)
    data.append(contentsOf: [0x41, 0x42, 0, 2])
    let event = Array("OnYuhnaRandomTalk".utf8)
    data.append(contentsOf: [0, UInt8(event.count)])
    data.append(contentsOf: event)
    data.append(contentsOf: [1, 0, 0, 0, 1, 0, 9, 1])
    let longScript = String(repeating: "a", count: 265)
    data.append(contentsOf: longScript.utf8)
    appendEvent("OnBoot", script: "boot", to: &data)
    try data.write(to: master.appending(path: "dic.ydf"))

    let engine = try YuhnaSession(masterDirectoryURL: master)
    #expect(try engine.request(request("OnAITalk")).value == longScript)
    #expect(try engine.request(request("OnBoot")).value == "boot")
}
