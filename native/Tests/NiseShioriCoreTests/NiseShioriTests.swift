import Foundation
import ModuleProtocol
import Testing
@testable import NiseShioriCore

@Test func niseSessionUsesWireEventsAndRestoresState() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let state = root.appending(path: "state/saved.json")
    try Data("#Charset: UTF-8\n\\ev,OnBoot & %hour>=0,\\0起動\\set[count=3]\\e\n\\ev,OnMouseDoubleClick & %get[count]=3,\\0クリック\\e\n".utf8)
        .write(to: root.appending(path: "ai.txt"))
    let boot = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    let click = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnMouseDoubleClick")]))
    let session = try NiseShioriSession(masterDirectoryURL: root, stateStoreURL: state)
    #expect(try session.request(boot).value == "\\0起動\\e")
    #expect(try NiseShioriSession(masterDirectoryURL: root, stateStoreURL: state).request(click).value == "\\0クリック\\e")
}

@Test func niseSessionReturnsNoContentForUnknownEvent() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("#Charset: UTF-8\n\\ev,OnBoot,hello\n".utf8).write(to: root.appending(path: "ai.txt"))
    let session = try NiseShioriSession(masterDirectoryURL: root)
    let response = try session.request(.init(method: "GET", headers: .init([.init(name: "ID", value: "Unknown")])))
    #expect(response.statusCode == 204)
}
