import Darwin
import Foundation
import SaoriCore
import SaoriRuntime
import Testing

private func owned(_ bytes: Data) -> UnsafeMutableRawPointer {
    let pointer = malloc(max(bytes.count, 1))!
    bytes.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: bytes.count)
    return pointer
}

private func send(_ session: ConventionalSaoriSession, _ wire: String, encoding: String.Encoding = .utf8) throws -> String {
    let data = try #require(wire.data(using: encoding))
    var length = Int32(data.count)
    let response = try #require(session.request(owned(data), &length))
    defer { free(response) }
    return try #require(String(data: Data(bytes: response, count: Int(length)), encoding: encoding))
}

private func load(_ session: ConventionalSaoriSession, _ directory: URL) -> Int32 {
    let path = Data(directory.path.utf8)
    return session.load(owned(path), Int32(path.count))
}

@Test func systemInfoABIAndLifecycle() throws {
    let session = ConventionalSaoriSession(kind: .cpuid)
    let root = FileManager.default.temporaryDirectory
    #expect(load(session, root) == 1)
    #expect(load(session, root) == 0)
    #expect(try send(session, "GET Version SAORI/1.0\r\nCharset: UTF-8\r\n\r\n").hasPrefix("SAORI/1.0 200"))
    #expect(try send(session, "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: os.name\r\n\r\n").contains("Result: macOS\r\n"))
    #expect(session.unload() == 1)
    #expect(try send(session, "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\n\r\n").hasPrefix("SAORI/1.0 503"))
    #expect(load(session, root) == 1)
    #expect(session.unload() == 1)
}

@Test func keywordUTF8AndShiftJISHaveOrderedResults() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SAORI 日本語 \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try #require("飲み物＝日本酒、酒\r\n場所＝酒場\r\n".data(using: .shiftJIS)).write(to: root.appending(path: "keyword.txt"))
    let session = ConventionalSaoriSession(kind: .kenonoke)
    #expect(load(session, root) == 1)
    for (charset, encoding) in [("UTF-8", String.Encoding.utf8), ("Shift_JIS", .shiftJIS)] {
        let result = try send(session, "EXECUTE SAORI/1.0\r\nCharset: \(charset)\r\nArgument0: GETKEYWORD\r\nArgument1: 酒場で日本酒を飲む\r\n\r\n", encoding: encoding)
        #expect(result.contains("Result: 場所\r\nValue0: 飲み物\r\n"))
    }
    #expect(session.unload() == 1)
}

@Test func malformedRequestsNeverExecuteClipboardCommands() throws {
    let copied = CopiedText()
    let session = ConventionalSaoriSession(kind: .textcopy2, textCopyHandler: { copied.set($0) })
    #expect(load(session, FileManager.default.temporaryDirectory) == 1)
    for headers in ["Argument1: bad\r\n", "Argument0: bad\r\nArgument0: bad\r\n", "Argument-1: bad\r\n", "Argument1024: bad\r\n", "Argument0: bad\r\nCharset: UTF-8\r\n"] {
        #expect(try send(session, "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\n\(headers)\r\n").hasPrefix("SAORI/1.0 400"))
    }
    #expect(copied.value == nil)
    let result = try send(session, "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: 日本語\r\nArgument1: 1\r\n\r\n")
    #expect(copied.value == "日本語")
    #expect(result.contains("Result: 日本語\r\n"))
    #expect(session.unload() == 1)
}

@Test func invalidOwnedBuffersAreRejected() {
    let session = ConventionalSaoriSession(kind: .cpuid)
    for count: Int32 in [-1, 0, 8 * 1024 * 1024 + 1] {
        var length = count
        #expect(session.request(owned(Data([1])), &length) == nil)
        #expect(length == 0)
        #expect(session.load(owned(Data([1])), count) == 0)
    }
    #expect(session.request(owned(Data([1])), nil) == nil)
    #expect(session.load(owned(Data([0xFF])), 1) == 0)
    #expect(session.load(owned(Data("relative".utf8)), 8) == 0)
}

@Test func wmoveRequiresAndUsesItsOwningWindows() throws {
    let session = ConventionalSaoriSession(kind: .wmove)
    let request = "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: GET_POSITION\r\nArgument1: kero\r\n\r\n"
    #expect(load(session, FileManager.default.temporaryDirectory) == 1)
    #expect(try send(session, request).hasPrefix("SAORI/1.0 501"))
    #expect(session.setWindowCallback(testWindows) == 0)
    #expect(session.unload() == 1)
    #expect(session.setWindowCallback(testWindows) == 1)
    #expect(load(session, FileManager.default.temporaryDirectory) == 1)
    #expect(try send(session, request).contains("Result: 100\r\nValue0: 125\r\nValue1: 150\r\n"))
    #expect(session.unload() == 1)
    // A later host must not inherit a callback into a released window owner.
    #expect(load(session, FileManager.default.temporaryDirectory) == 1)
    #expect(try send(session, request).hasPrefix("SAORI/1.0 501"))
}

private func testWindows(_ operation: Int32, _ scope: Int32, _: Int32, _: Int32, _ output: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard operation == 1, scope == 1, let output else { return 0 }
    output[0] = 100; output[1] = 200; output[2] = 50; output[3] = 80
    return 1
}

private final class CopiedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    var value: String? {
        lock.withLock { text }
    }

    func set(_ value: String) {
        lock.withLock { text = value }
    }
}
