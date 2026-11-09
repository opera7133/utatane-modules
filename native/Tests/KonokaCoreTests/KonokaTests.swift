import Foundation
@testable import KonokaCore
import ModuleProtocol
import Testing

private func fixture(_ text: String, encrypted: Bool = false) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("ai.txt\r\n".utf8).write(to: root.appending(path: "konoka.ini"))
    let data = Data(text.utf8)
    try (encrypted ? KonokaCipher.encode(data) : data).write(to: root.appending(path: encrypted ? "ai.xdi" : "ai.txt"))
    return root
}

private func get(_ id: String) -> ShioriRequest {
    .init(method: "GET", headers: .init([.init(name: "ID", value: id)]))
}

@Test func cipherRoundTrip() throws {
    for length in [0, 1, 2, 7, 8, 15, 63, 128, 1024] {
        let input = Data((String(repeating: "x", count: length) + "\r\n日本語\r\n\r\n").utf8)
        #expect(try KonokaCipher.decode(KonokaCipher.encode(input)) == input)
    }
    #expect(throws: KonokaError.self) { try KonokaCipher.decode(Data([255])) }
}

@Test func encryptedEventsMacrosExpressionsAndResources() throws {
    let root = try fixture("""
    $(zero),\\0
    \\animal,cat
    @OnBoot,(zero)%(2+3*4):%animal:%animal
    *homeurl,https://example.test/
    """, encrypted: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = try KonokaSession(masterDirectoryURL: root)
    #expect(try engine.request(get("OnBoot")).value == "\\014:cat:cat\\e")
    #expect(try engine.request(get("homeurl")).value == "https://example.test/")
    #expect(try engine.request(get("Unknown")).statusCode == 204)
}

@Test func allConditionsRunAndDirectReferencesSeeAssignments() throws {
    let root = try fixture(#"""
    @OnBoot & \count:=2;0,*
    @OnBoot & \count:=$count+3;0,*
    @OnBoot,%count
    @OnSave,%(\_save:=counter.%count;0)
    @OnRestore,%(\count:=(\_load:=counter);$count)
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = try KonokaSession(masterDirectoryURL: root)
    #expect(try engine.request(get("OnBoot")).value == "5\\e")
    _ = try engine.request(get("OnSave"))
    let next = try KonokaSession(masterDirectoryURL: root)
    #expect(try next.request(get("OnRestore")).value == "5\\e")
}

@Test func expressionEagerTernaryAndDivisionGuard() throws {
    var values: [String: String] = [:]
    var parser = try KonokaExpression(#"0 ? (\a:=1) : (\b:=2)"#)
    #expect(try KonokaExpression.evaluate(parser.parse(), read: { values[$0] ?? "" }, write: { values[$0] = $1; return $1 }) == "2")
    #expect(values == ["a": "1", "b": "2"])
    var zero = try KonokaExpression("1/0")
    #expect(try KonokaExpression.evaluate(zero.parse(), read: { _ in "" }, write: { _, value in value }) == "#div0!")
}

@Test func traversalAndCorruptStateFail() throws {
    let root = try fixture("@OnBoot,ok\n")
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("broken".utf8).write(to: root.appending(path: "konoka-state.json"))
    #expect(throws: (any Error).self) { try KonokaSession(masterDirectoryURL: root) }
    try FileManager.default.removeItem(at: root.appending(path: "konoka-state.json"))
    try Data("../outside.txt\n".utf8).write(to: root.appending(path: "konoka.ini"))
    #expect(throws: (any Error).self) { try KonokaSession(masterDirectoryURL: root) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_KONOKA_REAL_MASTER"] != nil, "Set UTATANE_KONOKA_REAL_MASTER to test a local ghost"))
func optionalRealKonokaDictionary() throws {
    let path = try #require(ProcessInfo.processInfo.environment["UTATANE_KONOKA_REAL_MASTER"])
    let state = FileManager.default.temporaryDirectory.appending(path: "konoka-real-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let engine = try KonokaSession(masterDirectoryURL: URL(fileURLWithPath: path), stateStoreURL: state)
    for id in ["OnBoot", "OnFirstBoot", "OnSecondChange", "OnMouseDoubleClick", "homeurl"] {
        let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: id)] + (0 ... 3).map { .init(name: "Reference\($0)", value: "0") }))
        _ = try engine.request(request)
    }
}

@Test func macrosUseParameterOrderAndSerialAndResourceSeparators() throws {
    let root = try fixture(#"""
    $[%9|%1],%1:%9
    $(serial),$N
    @OnBoot,[left|right]:(serial):(serial)
    \id,homeurl,a\[1]b\[2]c
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnBoot")).value == "right:left:1:2\\e")
    #expect(try session.request(get("homeurl")).value == "a\u{1}b\u{2}c")
}

@Test func cyclesAndSymlinksAreBoundedAndFailedRequestsRollBack() throws {
    let root = try fixture(#"""
    \recursive,%recursive!
    @OnBoot,%(\_save:=key.changed)%recursive
    @OnRead,%(\_load:=key)
    @OnLoop,@OnLoop
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    #expect(throws: KonokaError.self) { try session.request(get("OnBoot")) }
    #expect(try session.request(get("OnRead")).statusCode == 204)
    #expect(throws: KonokaError.self) { try session.request(get("OnLoop")) }
    try FileManager.default.removeItem(at: root.appending(path: "ai.txt"))
    try FileManager.default.createSymbolicLink(atPath: root.appending(path: "ai.txt").path, withDestinationPath: "/etc/hosts")
    #expect(throws: KonokaError.self) { try KonokaSession(masterDirectoryURL: root) }
}

@Test func persistedWordsMergeWithDictionaryAndNotifyHasNoScript() throws {
    let root = try fixture(#"""
    \word,original
    @OnRegister,%(\_registword:=word.learned)
    @OnCount,%(\_countword:=word)
    @OnRead,%word
    @OnAssign,%(\v:=temporary)
    @OnVariable,%v
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    _ = try session.request(get("OnAssign"))
    let notify = ShioriRequest(method: "NOTIFY", headers: .init([.init(name: "ID", value: "OnRegister")]))
    #expect(try session.request(notify).statusCode == 204)
    let next = try KonokaSession(masterDirectoryURL: root)
    #expect(try next.request(get("OnCount")).value == "2\\e")
    #expect(try next.request(get("OnVariable")).value == "%v\\e")
    let value = try #require(next.request(get("OnRead")).value)
    #expect(["original\\e", "learned\\e"].contains(value))
    // Remove the source word and verify that the learned entry survives independently.
    try Data("@OnRead,%word\n".utf8).write(to: root.appending(path: "ai.txt"))
    let learned = try KonokaSession(masterDirectoryURL: root)
    #expect(try learned.request(get("OnRead")).value == "learned\\e")
}

@Test func multilineMacrosEventsConditionsAndResources() throws {
    let root = try fixture(#"""
    $(setup),
    \count:=3;0

    @OnLoad & (setup),*
    @OnBoot &
    %count=3,
    first
    second

    \id,homeurl
    https://example.test/

    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnBoot")).value == "firstsecond\\e")
    #expect(try session.request(get("homeurl")).value == "https://example.test/")
}

@Test func decodesOriginalGeneratedXDILine() throws {
    // Original custom DLL's base-95 line, repacked at a byte boundary.
    // The source is a synthetic dictionary, not a redistributed ghost dictionary.
    let bytes: [UInt8] = [0x47, 0x8F, 0x23, 0xF7, 0xBB, 0xB2, 0x3C, 0x65, 0x61, 0x6C, 0x07, 0xCD, 0x6E, 0xA2, 0xD7, 0xF3, 0x2E, 0x99, 0x3A, 0x30, 0xF0, 0xE5, 0x59, 0x8D, 0x59, 0xD8, 0x3B, 0xF2, 0x62, 0x28]
    let expected = try #require("@OnBoot,合成テスト%(2+3*4)\r\n".data(using: .shiftJIS))
    #expect(try KonokaCipher.decode(Data(bytes)) == expected)
}

@Test func negativeArithmeticAndSnapshotReferences() throws {
    let root = try fixture(#"""
    @OnNegative,%(-3*2)
    @OnSet,%(\v:=7)
    @OnSnapshot,%(\v:=1;\v:=2;%v):%v
    @OnLiteral,%(\_save:=literal.word):%(\_load:=literal)
    \word,replacement
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnNegative")).value == "-6\\e")
    _ = try session.request(get("OnSet"))
    #expect(try session.request(get("OnSnapshot")).value == "7:2\\e")
    #expect(try session.request(get("OnLiteral")).value == "word:word\\e")
}

@Test func standardXDCMatchesOriginalDLL() throws {
    // Synthetic dictionary generated with the unmodified standard DLL from gaochan09.nar.
    let plain = try #require("@OnBoot,合成テスト%(2+3*4)\r\n".data(using: .shiftJIS))
    let encrypted = Data([0xFD, 0x04, 0x3F, 0x25, 0x49, 0x76, 0xA8, 0x93, 0xCF, 0x0E, 0x54, 0xAA, 0xEC, 0x0B, 0x42, 0x62, 0x8F, 0xB2, 0x94, 0x7E, 0x73, 0x5F, 0x44, 0x29, 0x15, 0xFD, 0xC6, 0x7C])
    #expect(try KonokaCipher.decode(encrypted, format: .xdc) == plain)
    #expect(try KonokaCipher.encode(plain, format: .xdc) == encrypted)
    let bytes = Data((0 ..< 4096).map { UInt8($0 & 255) })
    #expect(try KonokaCipher.decode(KonokaCipher.encode(bytes, format: .xdc), format: .xdc) == bytes)
    #expect(try KonokaCipher.encode(Data(), format: .xdc).isEmpty)
}

@Test func konokaLoadsXDCFallbackAndExplicitXDC() throws {
    let root = try fixture("@OnBoot,plain\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let data = try KonokaCipher.encode(Data("@OnBoot,XDC\r\n".utf8), format: .xdc)
    try data.write(to: root.appending(path: "ai.xdc"))
    #expect(try KonokaSession(masterDirectoryURL: root).request(get("OnBoot")).value == "plain\\e")
    try FileManager.default.removeItem(at: root.appending(path: "ai.txt"))
    #expect(try KonokaSession(masterDirectoryURL: root).request(get("OnBoot")).value == "XDC\\e")
    try Data("ai.xdc\r\n".utf8).write(to: root.appending(path: "konoka.ini"))
    #expect(try KonokaSession(masterDirectoryURL: root).request(get("OnBoot")).value == "XDC\\e")
}

@Test func konokaTeachStatusContextAndLiteralInputs() throws {
    let root = try fixture(#"""
    @OnTeach & %lastnum=,%word:%hint0\[shortage]
    @OnTeach & %lastnum<>,%word:%lasthint:%lastnum\[advice]
    @OnRead,%(\_load:=injected)
    \echo,%argv%
    @OnMacro,%(\echo:=%ref0)
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try KonokaSession(masterDirectoryURL: root)
    func teach(_ word: String, _ hints: [String]) -> ShioriRequest {
        .init(method: "GET", headers: .init([.init(name: "ID", value: "OnTeach"), .init(name: "Reference0", value: word)] + hints.enumerated().map { .init(name: "Reference\($0.offset + 1)", value: $0.element) }))
    }
    let first = try session.request(teach("apple", []))
    #expect(first.statusCode == 311)
    #expect(first.value == "apple:%hint0")
    let next = try session.request(teach("apple", ["cat", "dog"]))
    #expect(next.statusCode == 312)
    #expect(next.value == "apple:dog:1")
    let payload = #"%(\_save:=injected.yes)\[success]"#
    let literal = try session.request(teach(payload, []))
    #expect(literal.statusCode == 311)
    #expect(literal.value == payload + ":%hint0")
    #expect(try session.request(get("OnRead")).statusCode == 204)
    let macro = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnMacro"), .init(name: "Reference0", value: payload)]))
    #expect(try session.request(macro).value == payload + "\\e")
    #expect(try session.request(get("OnRead")).statusCode == 204)
}

@Test func konokaOriginalSaveImportBuiltinsAndAutomaticXDC() throws {
    let root = try fixture(#"""
    \one,alpha
    \two,alpha,beta
    @OnImport,%(\_load:=key)
    @OnBuiltins,%(\v:=5;\_isval:=v):%(\_get:=v):%(\_wordtype:=alpha):%(\_isval:=one)
    @OnRegister,%(\_registword:=one.gamma):%(\_registword:=one.gamma):%(\_countword:=one)
    @OnMiddle,%(\_middle:=a	b	c.0):%(\_middle:=a	b	c.2)
    """#.replacingOccurrences(of: #"\t"#, with: "\t"))
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("ai.txt,e\r\n".utf8).write(to: root.appending(path: "konoka.ini"))
    let original = Data("key,hello,world\r\n".utf8)
    try original.write(to: root.appending(path: "values.dat"))
    let session = try KonokaSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnImport")).value == "hello,world\\e")
    #expect(try session.request(get("OnBuiltins")).value == "1:5:one:0\\e")
    #expect(try session.request(get("OnRegister")).value == "gamma:gamma:2\\e")
    #expect(try session.request(get("OnMiddle")).value == "a:c\\e")
    #expect(try Data(contentsOf: root.appending(path: "values.dat")) == original)
    let encrypted = try Data(contentsOf: root.appending(path: "ai.xdc"))
    #expect(try KonokaCipher.decode(encrypted, format: .xdc) == Data(contentsOf: root.appending(path: "ai.txt")))
    try FileManager.default.removeItem(at: root.appending(path: "ai.txt"))
    #expect(try KonokaSession(masterDirectoryURL: root).request(get("OnImport")).value == "hello,world\\e")
}
