import Foundation
import ModuleProtocol
import Testing
@testable import EseShioriCore

private func request(_ id: String, references: [Int: String] = [:]) -> ShioriRequest {
    var headers = ShioriHeaders([.init(name: "ID", value: id)])
    for (index, value) in references.sorted(by: { $0.key < $1.key }) {
        headers.append(name: "Reference\(index)", value: value)
    }
    return ShioriRequest(method: "GET", headers: headers)
}

@Test func eseSessionUsesWireRequestsAndNormalizesMateriaSurfaces() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "[ESEAI]\nDIC_CHAR_SET=UTF-8\n".write(to: root.appending(path: "eseai.ini"),
                                              atomically: true, encoding: .utf8)
    try "##EVNT=(\"OnBoot\")\n\\1\\s1起動\\e\n".write(to: root.appending(path: "eseai_boot.txt"),
                                                   atomically: true, encoding: .utf8)
    let session = try EseShioriSession(masterDirectoryURL: root)
    let response = try session.request(request("OnBoot"))
    #expect(response.statusCode == 200)
    #expect(response.value == "\\1\\s[11]起動\\e")
    #expect(try session.request(request("Unknown")).statusCode == 204)
}

@Test func eseSessionReusesLegacyStateAndKeepsWrittenFilesOutsideGhost() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master")
    let state = root.appending(path: "state/ese-shiori-state.json")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "[ESEAI]\nDIC_CHAR_SET=UTF-8\n".write(to: master.appending(path: "eseai.ini"),
                                              atomically: true, encoding: .utf8)
    try "##EVNT=(\"OnProbe\")\n$POP(4)$PUSH(\"hello\",1,0)$WRITEFILE(\"USER.DAT\",1,1)\n"
        .write(to: master.appending(path: "eseai_probe.txt"), atomically: true, encoding: .utf8)
    try #"{"variables":{},"storage":{"4":"legacy"},"learnedEntries":{},"talkInterval":null,"talkSeconds":0,"newsInterval":null,"newsCounters":{}}"#
        .write(to: state, atomically: true, encoding: .utf8)
    let session = try EseShioriSession(masterDirectoryURL: master, stateStoreURL: state)
    #expect(try session.request(request("OnProbe")).value == "legacy")
    #expect(try String(contentsOf: root.appending(path: "state/ese-shiori-files/USER.DAT"), encoding: .utf8) == "hello\r\n")
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "USER.DAT").path))
    try session.save()
    #expect(try EseShioriSession(masterDirectoryURL: master, stateStoreURL: state)
        .request(request("OnProbe")).value == "legacy")
}

@Test func eseSessionLoadsOriginalGhostWhenAvailable() throws {
    guard let path = ProcessInfo.processInfo.environment["ESE_SHIORI_SAMPLE_MASTER"] else { return }
    let master = URL(fileURLWithPath: path)
    let state = FileManager.default.temporaryDirectory.appending(path: "ese-sample-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let session = try EseShioriSession(masterDirectoryURL: master, stateStoreURL: state)
    let response = try session.request(request("OnBoot"))
    #expect(response.value?.isEmpty == false)
}
