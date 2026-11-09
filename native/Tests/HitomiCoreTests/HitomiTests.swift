import Foundation
@testable import HitomiCore
import ModuleProtocol
import Testing

private func fixture(_ source: String, encrypted: Bool = false) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "Hitomi 日本語 \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("dict: ai.txt\r\n".utf8).write(to: root.appending(path: "kawari.ini"))
    var data = Data()
    for line in source.components(separatedBy: "\n") {
        let bytes = try #require(line.data(using: .shiftJIS))
        data += encrypted ? try HitomiCipher.encodeLine(bytes) : bytes
        data += Data([13, 10])
    }
    try data.write(to: root.appending(path: "ai.txt"))
    return root
}

private func get(_ id: String, refs: [String] = []) -> ShioriRequest {
    .init(method: "GET", headers: .init([.init(name: "ID", value: id)] + refs.enumerated().map { .init(name: "Reference\($0.offset)", value: $0.element) }))
}

@Test func hitomiCipherMatchesKawari042Format() throws {
    #expect(try HitomiCipher.encodeLine(Data("abc".utf8)) == Data("!KAWA0000ra6v".utf8))
    #expect(try HitomiCipher.decodeLine(Data("!KAWA0000ra6v".utf8)) == Data("abc".utf8))
    #expect(try HitomiCipher.decodeLine(HitomiCipher.encodeLine(Data([0x82, 0xA0, 0x5C]))) == Data([0x82, 0xA0, 0x5C]))
    #expect(throws: HitomiError.self) { try HitomiCipher.decodeLine(Data("!KAWA0000@@".utf8)) }
    #expect(throws: HitomiError.self) { try HitomiCipher.encodeLine(Data([10])) }
}

@Test func hitomiEventsReferencesLocalWordsAndEncryption() throws {
    let root = try fixture(#"""
    word: 日本語
    username: User
    ?OnUser: ${username}
    @local: 局所
    ?OnBoot: \0${word}:${0}:${@local}\e
    ?OnEcho: ${!Reference0}:${!Reference7}\e
    sentence: 通常\e
    """#, encrypted: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnBoot")).value == "\\0日本語:日本語:局所\\e")
    #expect(try session.request(get("OnUser")).value == "User")
    #expect(try session.request(get("OnEcho", refs: ["😀", "", "", "", "", "", "", "末尾"])).value == "😀:末尾\\e")
    #expect(try session.request(get("OnEcho")).value == "!Reference0:!Reference7\\e")
    #expect(try session.request(get("OnAITalk")).value == "通常\\e")
    #expect(try session.request(get("Unknown")).statusCode == 204)
}

@Test func hitomiCommunicationAndNotify() throws {
    let root = try fixture(#"""
    ?hello: exact\e
    ?silence: quiet\e
    ?switch: fallback:${!instant}\e
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnCommunicate", refs: ["user", "hello"])).value == "exact\\e")
    #expect(try session.request(get("OnCommunicate", refs: ["user", ""])).value == "quiet\\e")
    #expect(try session.request(get("OnCommunicate", refs: ["user", "unknown"])).value == "fallback:unknown\\e")
    let notify = ShioriRequest(method: "NOTIFY", headers: get("OnAITalk").headers)
    #expect(try session.request(notify).statusCode == 204)
}

@Test func hitomiRejectsUnsupportedLaterGrammarAndUnsafePaths() throws {
    let root = try fixture("?OnBoot & ${x} equal yes: bad\n")
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
    try Data("dict: ../outside.txt\n".utf8).write(to: root.appending(path: "kawari.ini"))
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
    try Data("dict: ai.txt\n".utf8).write(to: root.appending(path: "kawari.ini"))
    try FileManager.default.removeItem(at: root.appending(path: "ai.txt"))
    try FileManager.default.createSymbolicLink(atPath: root.appending(path: "ai.txt").path, withDestinationPath: "/etc/hosts")
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
}

@Test func hitomiBoundsRecursionAndMalformedReferences() throws {
    let root = try fixture("?OnBoot: ${loop}\nloop: ${loop}\n")
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(throws: HitomiError.self) { try session.request(get("OnBoot")) }
    try Data("?OnBad: ${broken\n".utf8).write(to: root.appending(path: "ai.txt"))
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
    #expect(try session.request(get("Unknown")).statusCode == 204)
}

@Test func hitomi046ConditionsOptionsPreprocessorAndLists() throws {
    let root = try fixture(#"""
    #define ENABLED
    #ifdef ENABLED
    ?#OnBoot & ${!Reference0} >= 3 & ${!Reference0} found "3" : numeric
    ?#OnBoot . : other
    #else
    ?#OnBoot : wrong
    #endif
    ?#OnMouseDoubleClick "head" : hit
    ?#OnMouseDoubleClick . : miss
    values,other : cat,dog
    common : dog,fox
    ?#OnUnion : $Length{values|common}
    ?#OnIntersection : ${values&common}
    ?#OnQuoted : ${"a,b"}
    ?#OnEmpty & ${missing} empty : empty
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("dict: ai.txt\r\n".utf8).write(to: root.appending(path: "hitomi.ini"))
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnBoot", refs: ["3"])).value == "numeric")
    #expect(try session.request(get("OnBoot", refs: ["2"])).value == "other")
    #expect(try session.request(get("OnMouseDoubleClick", refs: ["0", "0", "0", "0", "head"])).value == "hit")
    #expect(try session.request(get("OnMouseDoubleClick", refs: ["0", "0", "0", "0", "body"])).value == "miss")
    #expect(try session.request(get("OnUnion")).value == "3")
    #expect(try session.request(get("OnIntersection")).value == "dog")
    #expect(try session.request(get("OnQuoted")).value == "a,b")
    #expect(try session.request(get("OnEmpty")).value == "empty")
}

@Test func hitomi046PSYCountersAndSavedWordsSurviveRestart() throws {
    let root = try fixture(#"""
    ?OnInc : $Inc{"counter"}$Get{"counter"}
    ?OnSet : $SetWord{"slot","a","b"}$Join{"-",~Word.slot}
    ?OnShow : $Join{"-",~Word.slot}
    ?OnGet : $Get{"counter"}:$Length{~Word.slot}
    ?OnLists : $Join{"-","a","b"}:$First{"x","y"}:$Length{"a","b"}
    ?OnFail : $Inc{"counter"}$Unknown{}
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let stateDir = root.appending(path: "state")
    let stateURL = stateDir.appending(path: "native.json")
    let session = try HitomiSession(masterDirectoryURL: root, stateStoreURL: stateURL)
    #expect(try session.request(get("OnInc")).value == "1")
    #expect(try session.request(get("OnSet")).statusCode == 204)
    #expect(try session.request(get("OnShow")).value == "a-b")
    #expect(try session.request(get("OnLists")).value == "a-b:x:2")
    #expect(throws: HitomiError.self) { try session.request(get("OnFail")) }
    #expect(try session.request(get("OnGet")).value == "1:2")
    let next = try HitomiSession(masterDirectoryURL: root, stateStoreURL: stateURL)
    #expect(try next.request(get("OnGet")).value == "1:2")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "hitomi.dat").path))
    try Data("broken".utf8).write(to: stateURL)
    #expect(throws: (any Error).self) { try HitomiSession(masterDirectoryURL: root, stateStoreURL: stateURL) }
    #expect(try Data(contentsOf: stateURL) == Data("broken".utf8))
}

@Test func hitomi046HeartsImportTeachAndPreferencesPersistOutsideSource() throws {
    let root = try fixture(#"""
    ?#HitomiStudyNewWord : NEW:${!keyword}:${!teachword}
    ?#HitomiStudyRequire : REQUIRE:${!keyword}:${!teachword}
    ?#HitomiStudyReject : REJECT:${!keyword}:${!teachword}
    ?#HitomiStudySameKey : SAME:${!keyword}:${!teachword}
    ?#HitomiStudyCommit : COMMIT:${!keyword}:${!teachword}
    ?#OnCheck : $Hearts.Exist{"apple"}:$Hearts.GetRelation{"apple"}
    ?#OnLove : $Hearts.Love{"cat"}$Hearts.Like{"cat"}
    ?like : LIKE:${!like}
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("dict: ai.txt\r\n".utf8).write(to: root.appending(path: "hitomi.ini"))
    try Data("Hearts.dict: memory.txt\r\n".utf8).write(to: root.appending(path: "psy.ini"))
    let original = Data("Myself: Native,0\r\nMaster: User,0\r\nWord: cat,0\r\n".utf8)
    try original.write(to: root.appending(path: "memory.txt"))
    let stateURL = root.appending(path: "state/native.json")
    let session = try HitomiSession(masterDirectoryURL: root, stateStoreURL: stateURL)
    let cases: [([String], Int, String)] = [
        (["apple"], 311, "NEW:apple:"),
        (["apple", "unknown"], 311, "REJECT:apple:unknown"),
        (["apple", "apple"], 312, "SAME:apple:apple"),
        (["apple", "cat"], 311, "REQUIRE:apple:cat"),
        (["apple", "cat", "cat"], 311, "REQUIRE:apple:cat"),
        (["apple", "cat", ""], 200, "COMMIT:apple:"),
    ]
    for (refs, status, text) in cases {
        let response = try session.request(get("OnTeach", refs: refs))
        #expect(response.statusCode == status)
        #expect(response.value == text)
    }
    #expect(try session.request(get("OnCheck")).value == "apple:cat")
    #expect(try session.request(get("OnLove")).value == "cat")
    #expect(try session.request(get("OnCommunicate", refs: ["user", "cat"])).value == "LIKE:cat")
    let next = try HitomiSession(masterDirectoryURL: root, stateStoreURL: stateURL)
    #expect(try next.request(get("OnCheck")).value == "apple:cat")
    #expect(try Data(contentsOf: root.appending(path: "memory.txt")) == original)
}

@Test func hitomi046RelationDeduplicationAndStateImport() throws {
    let root = try fixture(#"""
    ?OnLink : $Hearts.Set.Relation{"cat","dog"}$Hearts.Set.Relation{"cat","dog"}$Hearts.Set.Relation{"fox","dog"}
    ?OnQuery : $Length{|~Word.slot}:$Get{"counter"}:$Length{"a","b"}
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("Hearts.dict: memory.txt\n".utf8).write(to: root.appending(path: "psy.ini"))
    let memory = Data("Word: cat,0\nWord: dog,0\nWord: fox,0\n".utf8)
    let previous = Data("Counter.counter : 7\nWord.slot : kept\nString.homeurl : https://example.test/kept\n".utf8)
    try memory.write(to: root.appending(path: "memory.txt"))
    try previous.write(to: root.appending(path: "hitomi.dat"))
    let session = try HitomiSession(masterDirectoryURL: root)
    _ = try session.request(get("OnLink"))
    #expect(try session.request(get("OnQuery")).value == "1:7:2")
    #expect(try session.request(get("homeurl")).value == "https://example.test/kept")
    let next = try HitomiSession(masterDirectoryURL: root)
    #expect(try next.request(get("homeurl")).value == "https://example.test/kept")
    let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "hitomi-native-state.json"))) as? [String: Any])
    let hearts = try #require(json["hearts"] as? [String: Any])
    let words = try #require(hearts["words"] as? [String: [String: Any]])
    #expect(words["dog"]?["relations"] as? [String: Int] == ["cat": 500, "fox": 500])
    #expect(try Data(contentsOf: root.appending(path: "hitomi.dat")) == previous)
    #expect(try Data(contentsOf: root.appending(path: "memory.txt")) == memory)
}

@Test func hitomi046OneShotPreprocessorAndInvalidMemoryAreBounded() throws {
    let root = try fixture(#"""
    #if0
    ?OnBoot: $Unknown{}
    #endif
    ?#OnOnce : ${?%once}
    ?%once : first
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnOnce")).value == "first")
    #expect(try session.request(get("OnOnce")).statusCode == 204)
    #expect(try session.request(get("OnBoot")).statusCode == 204)
    try Data("Hearts.dict: memory.txt\n".utf8).write(to: root.appending(path: "psy.ini"))
    try Data("Word: cat,0,dog,-1\n".utf8).write(to: root.appending(path: "memory.txt"))
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
    try Data("Hearts.dict: ../outside.txt\n".utf8).write(to: root.appending(path: "psy.ini"))
    #expect(throws: HitomiError.self) { try HitomiSession(masterDirectoryURL: root) }
}

@Test func hitomiIncomingTextAndSavedAtomsCannotExecutePSY() throws {
    let root = try fixture(#"""
    ?#OnEcho : ${!Reference0}
    ?#OnStore : $SetWord{"slot",!Reference0}
    ?#OnSaved : ${~Word.slot}
    ?#OnCount : $Get{"count"}
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    let payload = #"$Inc{"count"}"#
    #expect(try session.request(get("OnEcho", refs: [payload])).value == payload)
    _ = try session.request(get("OnStore", refs: [payload]))
    #expect(try session.request(get("OnSaved")).value == payload)
    #expect(try session.request(get("OnCount")).value == "0")
    let next = try HitomiSession(masterDirectoryURL: root)
    #expect(try next.request(get("OnSaved")).value == payload)
    #expect(try next.request(get("OnCount")).value == "0")
}

@Test func hitomi046PSYQueriesDatesAndUserName() throws {
    let root = try fixture(#"""
    ?#OnDate: $MakeDateString{"2024","02","03","04","05","06"}
    ?#OnLoad: $Hearts.Load.Words{}:$Length{!psy}
    ?#OnHolder: $Hearts.RelationHolder{"cat","dog","Bob"}:$Length{!psy}
    ?#OnCommon: $Hearts.CommonRelation{"cat","dog"}
    ?#OnStudy: $Hearts.Study{"new","cat","dog"}:$Length{!psy}
    ?#OnFriend: $Hearts.Exist.Friends{"Bob"}
    ?#OnUser: $UserName{"Named"}${username}
    ?#OnRead: ${username}:${~String.username}
    ?#OnTmp: $Tmp{"a","b"}ok
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("dict: ai.txt\nString.username: Old\n".utf8).write(to: root.appending(path: "hitomi.ini"))
    try Data("Hearts.dict: memory.txt\ndateForm: %year/%month/%day %hour:%minute:%second\n".utf8).write(to: root.appending(path: "psy.ini"))
    try Data("Word: cat,0,fox,1000\nWord: dog,0,fox,1000\nWord: fox,0\nFriend: Bob,0\n".utf8).write(to: root.appending(path: "memory.txt"))
    let session = try HitomiSession(masterDirectoryURL: root)
    #expect(try session.request(get("OnDate")).value == "2024/2/3 4:5:6")
    #expect(try ["cat:3", "dog:3", "fox:3"].contains(session.request(get("OnLoad")).value ?? ""))
    #expect(try ["cat:2", "dog:2"].contains(session.request(get("OnHolder")).value ?? ""))
    #expect(try session.request(get("OnCommon")).value == "fox")
    #expect(try ["cat:2", "dog:2"].contains(session.request(get("OnStudy")).value ?? ""))
    #expect(try session.request(get("OnFriend")).value == "Bob")
    #expect(try session.request(get("OnUser")).value == "Old")
    #expect(try session.request(get("OnRead")).value == "Named:Named")
    #expect(try session.request(get("OnTmp")).value == "ok")
    let next = try HitomiSession(masterDirectoryURL: root)
    #expect(try next.request(get("OnRead")).value == "Named:Named")
    #expect(try next.request(get("OnDate")).value == "2024/2/3 4:5:6")
}

@Test func hitomi046TimersUseRequestClockAndFireOnce() throws {
    let root = try fixture(#"""
    ?#OnStart: $SetTimer{"2","#Tick"}
    ?#OnDefault: $SetTimer{"1"}
    ?#Tick: tick:${!Reference0}
    ?#HitomiTimer: default
    ?#OnReset: $ResetTimer{}
    """#)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try HitomiSession(masterDirectoryURL: root)
    func at(_ id: String, _ second: TimeInterval) throws -> ShioriResponse {
        try session.request(get(id, refs: ["100", "0", "0", "1"]), now: Date(timeIntervalSince1970: second))
    }
    #expect(try at("OnStart", 100).statusCode == 204)
    #expect(try at("OnSecondChange", 102).statusCode == 204)
    #expect(try at("OnSecondChange", 103).value == "tick:100")
    #expect(try at("OnSecondChange", 104).statusCode == 204)
    _ = try at("OnDefault", 105)
    #expect(try at("OnSecondChange", 107).value == "default")
    _ = try at("OnStart", 110)
    _ = try at("OnReset", 111)
    #expect(try at("OnSecondChange", 113).statusCode == 204)
}
