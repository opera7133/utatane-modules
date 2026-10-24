import Foundation
import Testing
@testable import SaoriCore

@Test func httpcSynchronousCompatibilityReturnsAllMatchesAndSavesExactBytes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let body = Data("<a>日本語</a>\r\n<a>次</a>".utf8)
    let module = NativeHttpc(directory: root, connected: { true }, fetch: { url in
        url.path == "/fail" ? nil : (body, "UTF-8")
    })
    #expect(module.call([]) == "1")
    #expect(module.call(["http://localhost/data"]) == "<a>日本語</a><a>次</a>")
    let args = ["http://localhost/data", "<a>", "</a>"]
    #expect(module.callValues(args) == ["日本語", "次"])
    #expect(module.callValues(args) == ["日本語", "次"])
    #expect(module.call(["erase_tag", "utf8", "http://localhost/data"]) == "日本語次")
    #expect(module.call(["translate_tag", "http://localhost/data"]) == #"日本語\_a次\_a"#)
    module.unload()
    #expect(module.call(args) == "日本語")
    #expect(module.call(["http://localhost/data", "保存.bin"]) == "1")
    #expect(try Data(contentsOf: root.appending(path: "保存.bin")) == body)
    #expect(module.call(["http://localhost/fail", "保存.bin"]) == "0")
    #expect(try Data(contentsOf: root.appending(path: "保存.bin")) == body)
    #expect(module.call(["file:///etc/hosts"]) == "")
    #expect(module.call(["bg", "id", "http://localhost/data"]) == "")
}
