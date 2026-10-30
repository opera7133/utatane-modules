import Foundation
import ModuleProtocol
import Testing
@testable import MaeCore

struct MaeTests {
    func fixture(_ corpus: String, files: [String: String] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "mae 日本語 \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try corpus.write(to: root.appending(path: "mae_corpus.txt"), atomically: true, encoding: .utf8)
        for (name, text) in files { try text.write(to: root.appending(path: name), atomically: true, encoding: .utf8) }
        return root
    }
    func get(_ id: String, references: [String] = [], method: String = "GET", extra: [ShioriHeader] = []) -> ShioriRequest {
        var headers = ShioriHeaders([ShioriHeader(name: "ID", value: id)] + extra)
        for (i, value) in references.enumerated() { headers.append(name: "Reference\(i)", value: value) }
        return ShioriRequest(method: method, headers: headers)
    }
    @Test func lifecyclePersistenceArraysAndFunctions() throws {
        let root = try fixture("""
        #Declaration:
        var counter, cells[2], result;
        :end
        #Initialize:
        counter = counter + 1;
        :end
        #OnBoot:
        cells[0] = 3;
        cells[1] = 4;
        result = add(cells, counter);
        :end
        ${result}
        #Finalize:
        counter = counter + 10;
        :end
        """, files: ["mae_commonfunc.txt": "def add(a&, b) return a[0] + a[1] + b; end"])
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try MaeSession(masterDirectoryURL: root)
        #expect(try first.request(get("OnBoot")).value == "8")
        try first.close(); try first.close()
        let second = try MaeSession(masterDirectoryURL: root)
        #expect(try second.request(get("OnBoot")).value == "19")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "mae_variable.txt").path))
    }
    @Test func conditionPriorityAliasSlotAndReference() throws {
        let root = try fixture("""
        #起動:case reference[0] == 0 && strcmp(reference[0], "shell") == 0
        :end
        incorrect
        #OnBoot.shell.slot1:case hour == 18
        :end
        specific
        #起動
        fallback
        """, files: ["mae_actions.txt": "OnBoot\t起動", "mae.ini": "BEGIN_SLOT1=17\nEND_SLOT1=19"])
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 18))!
        let session = try MaeSession(masterDirectoryURL: root, clock: { date })
        #expect(try session.request(get("OnBoot", references: ["shell"])).value == "specific")
        #expect(try session.request(get("OnBoot", references: ["other"])).value == "fallback")
    }
    @Test func integerPrecedenceShortCircuitLoopAndReferences() throws {
        let root = try fixture("""
        #Declaration:
        var i, total, text, array[3];
        :end
        #OnBoot:
        i = 0; total = 0;
        while i < 10 do
        i = i + 1;
        if i == 3 then continue; end
        total = total + i;
        if i == 7 then break; end
        end
        if 0 && 1 / 0 then total = 99; end else total = total + 1; end
        text = sprint(total, ":", 2147483647 + 1, ":", 2 + 3 * 4);
        change(total);
        :end
        ${text}:${total}
        """, files: ["mae_commonfunc.txt": "def change(n&) n = n + 1; end"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnBoot")).value == "26:-2147483648:14:27")
    }
    @Test func splitJoinAndNewsRoundTrip() throws {
        let root = try fixture("""
        #Declaration:
        var array[3], text, revision, output;
        :end
        #OnBoot:
        revision = split(array, ",;", "one,two;three;four");
        text = join(2, "/", array);
        setnews("news", text, 0);
        setnews("news", "new", 0);
        revision = getnews("news", 1, output);
        :end
        ${text}:${revision}:${output}
        #OnRead:
        revision = getnews("news", 0, output);
        :end
        ${revision}:${output}
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnBoot")).value == "one/two:1:one/two")
        try session.close()
        let second = try MaeSession(masterDirectoryURL: root)
        #expect(try second.request(get("OnRead")).value == "2:new")
    }
    @Test func sequentialAndRandomWithoutReplacement() throws {
        let root = try fixture("""
        #OnBoot
        one
        two
        #OnRandom:
        setrandindex(0);
        :end
        a
        b
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root, choose: { _ in 0 })
        #expect(try session.request(get("OnBoot")).value == "one")
        #expect(try session.request(get("OnBoot")).value == "two")
        #expect(try session.request(get("OnBoot")).value == "one")
        #expect(try session.request(get("OnRandom")).value == "a")
        #expect(try session.request(get("OnRandom")).value == "b")
        #expect(try session.request(get("OnRandom")).value == "a")
    }
    @Test func moodDictionaryGenresAndFragments() throws {
        let root = try fixture("""
        #OnBoot
        ${場所}:${%1}:${\\dpart}\\s[笑顔]
        #OnMood:
        setsenti(20);
        :end
        neutral
        (価値観 1) happy
        """, files: ["places.dic": "(品詞 (名詞 一般)) ((見出し語 (駅 100))) (ジャンル 場所) (タイトル 鉄道) (価値観 3)",
                      "mae_alias.txt": "\\dpart part.txt", "part.txt": "${場所}", "mae_surface.txt": "5 笑顔"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root, choose: { _ in 0 })
        #expect(try session.request(get("OnBoot")).value == "駅:駅:駅\\s[5]")
        #expect(try session.request(get("OnMood")).value == "happy")
    }
    @Test func externalSecurityNotifyAndTalkTimer() throws {
        let root = try fixture("#OnBoot\nhello\n#Mae.Talk\ntalk", files: ["mae.ini": "TALK_INTERVAL=0\nTALK_INTERVAL_DETAIL=2"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnBoot", extra: [ShioriHeader(name: "SecurityLevel", value: "external")])).statusCode == 204)
        #expect(try session.request(get("OnBoot", method: "NOTIFY")).statusCode == 204)
        #expect(try session.request(get("OnSecondChange")).statusCode == 204)
        #expect(try session.request(get("OnSecondChange")).value == "talk")
    }
    @Test func invalidProgramAndBoundedExecution() throws {
        let root = try fixture("#OnBoot:\nwhile 1 do end\n:end\nunreachable")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(throws: MaeError.self) { try session.request(get("OnBoot")) }
        try "#OnBoot:\nvar a[2]; a[2] = 1;\n:end\nx".write(to: root.appending(path: "mae_corpus.txt"), atomically: true, encoding: .utf8)
        let broken = try MaeSession(masterDirectoryURL: root)
        #expect(throws: MaeError.self) { try broken.request(get("OnBoot")) }
        try "#OnBoot:case (\n:end\nx".write(to: root.appending(path: "mae_corpus.txt"), atomically: true, encoding: .utf8)
        #expect(throws: MaeError.self) { try MaeSession(masterDirectoryURL: root) }
    }
    @Test func referenceToArrayElementUpdatesCaller() throws {
        let root = try fixture("#Declaration:\nvar array[2];\n:end\n#OnBoot:\nchange(array[1]);\n:end\n${%info0}", files: ["mae_commonfunc.txt": "def change(n&) n = 17; end"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        _ = try session.request(get("OnBoot"))
        #expect(try session.vm.globals.cell("array").value.elements[1] == .integer(17))
        var parser = try MaeParser("array = 1;")
        #expect(throws: MaeError.self) { try session.vm.run(parser.program(), session.vm.globals) }
    }
    @Test func userFunctionCannotReadGlobalUserVariables() throws {
        let root = try fixture("#Declaration:\nvar secret;\n:end\n#OnBoot:\nsecret = hidden();\n:end\nx", files: ["mae_commonfunc.txt": "def hidden() return secret; end"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(throws: MaeError.self) { try session.request(get("OnBoot")) }
    }
    @Test func importOriginalSaveAndNewsWithoutRewritingThem() throws {
        let variables = #"""
        counter,1,0,0,22,""
        literal,1,0,1,0,"日本語\,\"引用\"\\末尾\n次の行"
        result,1,0,3,0,"関数の文字列"
        array,2,0,0,-123,""
        array,2,1,1,0,""
        array,2,500,0,99,""
        obsolete,1,0,0,1,""
        """#
        let ticks = UInt64(1_700_000_000 + 11_644_473_600) * 10_000_000
        let record = "headline,7,\(UInt32(truncatingIfNeeded: ticks)),\(UInt32(ticks >> 32)),\"保存\\,News\\n改行\""
        let root = try fixture("""
        #Declaration:
        var counter, literal, result, array[2];
        :end
        #Initialize:
        counter = counter + 1;
        :end
        #OnBoot
        ${counter}:${result}
        """, files: ["mae_variable.txt": variables, "mae_news.txt": record])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnBoot")).value == "23:関数の文字列")
        #expect(try session.vm.globals.cell("literal").value.text == "日本語,\"引用\"\\末尾\n次の行")
        #expect(try session.vm.globals.cell("array").value == .array([.integer(-123), .string("")]))
        #expect(session.news["headline"]?.first?.revision == 7)
        #expect(session.news["headline"]?.first?.text == "保存,News\n改行")
        #expect(session.news["headline"]?.first?.date == Calendar.current.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 22, minute: 13, second: 20)))
        try session.close()
        #expect(try String(contentsOf: root.appending(path: "mae_variable.txt"), encoding: .utf8) == variables)
        #expect(try String(contentsOf: root.appending(path: "mae_news.txt"), encoding: .utf8) == record)
        // Once JSON exists the stale original file must never be imported again.
        try "broken".write(to: root.appending(path: "mae_variable.txt"), atomically: true, encoding: .utf8)
        let second = try MaeSession(masterDirectoryURL: root)
        #expect(try second.request(get("OnBoot")).value == "24:関数の文字列")
    }
    @Test func cp932BackslashRemainsAnEscapeInCorpusAndSavedStrings() throws {
        let root = try fixture("#OnBoot\nx")
        defer { try? FileManager.default.removeItem(at: root) }
        // CP932 あ + ASCII backslash quote, comma and backslash n.
        let japanese = Data([0x82, 0xA0])
        var corpus = Data("#Declaration:\nvar text;\n:end\n#OnBoot:\ntext = \"".utf8)
        corpus.append(japanese); corpus.append(Data(#"\"quote\"\nline"#.utf8))
        corpus.append(Data("\";\n:end\n${text}".utf8))
        try corpus.write(to: root.appending(path: "mae_corpus.txt"))
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnBoot")).value == "あ\"quote\"\\nline")
        var saved = Data("text,1,0,1,0,\"".utf8); saved.append(japanese)
        saved.append(Data(#"\,\"quote\"\nline"#.utf8)); saved.append(Data("\"\r\n".utf8))
        try saved.write(to: root.appending(path: "mae_variable.txt"))
        let imported = try MaeSession(masterDirectoryURL: root)
        #expect(try imported.vm.globals.cell("text").value.text == "あ,\"quote\"\nline")
    }
    @Test func malformedOriginalStateFailsWithoutOverwriting() throws {
        let root = try fixture("#OnBoot\nx", files: ["mae_news.txt": "h,1,4294967296,0,\"x\""])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: MaeError.self) { try MaeSession(masterDirectoryURL: root) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "mae-native-state.json").path))
    }
    @Test func originalDefaultsAndRenamedSystemVariables() throws {
        let canonical = ["year", "month", "day", "hour", "minute", "second", "dayofweek", "username", "emotion", "reference[8]"]
        let system = canonical.map { "var renamed_\($0);" }.joined(separator: "\n") + "\nend"
        let root = try fixture("#OnBoot\n${renamed_hour}\n#OnReference:case strcmp(renamed_reference[0], \"hello\") == 0\n:end\nyes", files: ["mae_systemvar.txt": system])
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 18))!
        let session = try MaeSession(masterDirectoryURL: root, clock: { date })
        #expect(try session.request(get("OnBoot")).value == "18")
        #expect(try session.request(get("OnReference", references: ["hello"])).value == "yes")
        #expect(session.configuration["M2_SENTI_THRESHOLD"] == "-20")
        #expect(session.configuration["TALK_INTERVAL_ADDITION"] == "30")
        #expect(session.candidates(["OnBoot"]) == ["OnBoot.slot4", "OnBoot"])
        session.setSentiment(-21); #expect(session.emotion == -2)
        session.setSentiment(31); #expect(session.emotion == 2)
    }
    @Test func newsDateElapsedOverwriteDeleteAndMissingResults() throws {
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let root = try fixture("""
        #Declaration:
        var revision, message, y, m, d, h, minute, second;
        :end
        #Write:
        revision = setnews("h", reference[0], reference[1]);
        :end
        ${revision}
        #Date:
        revision = getnewsdate("h", 0, y, m, d, h, minute, second);
        :end
        ${revision}:${y}
        #Elapsed:
        revision = getnewselapsedtime("h", 0, h, minute, second);
        :end
        ${revision}:${h}:${minute}:${second}
        #Delete:
        revision = deletenews("h", 0, 1);
        :end
        ${revision}
        #Missing:
        revision = getnewsdate("missing", 0, y, m, d, h, minute, second);
        :end
        ${revision}:${y}:${second}
        """)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root, clock: { date })
        #expect(try session.request(get("Write", references: ["old", "0"])).value == "1")
        #expect(try session.request(get("Write", references: ["new", "1"])).value == "1")
        #expect(session.news["h"]?.count == 1)
        #expect(try session.request(get("Date")).value == "1:2023")
        date.addTimeInterval(3661)
        #expect(try session.request(get("Elapsed")).value == "1:1:1:1")
        #expect(try session.request(get("Delete")).value == "1")
        #expect(try session.request(get("Missing")).value == "0::")
    }
    @Test func notifyAndCannotTalkDoNotConsumeTalkSequence() throws {
        let root = try fixture("#Declaration:\nvar count;\n:end\n#OnCount:\ncount = count + 1;\n:end\n#OnQuery\n${count}\n#Mae.Talk\none\ntwo", files: ["mae.ini": "TALK_INTERVAL=0\nTALK_INTERVAL_DETAIL=1"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        #expect(try session.request(get("OnCount", method: "NOTIFY")).statusCode == 204)
        #expect(try session.request(get("OnQuery")).value == "1")
        #expect(try session.request(get("Mae.Talk", method: "NOTIFY")).statusCode == 204)
        #expect(try session.request(get("OnSecondChange", references: ["0", "0", "0", "0"])).statusCode == 204)
        #expect(try session.request(get("OnSecondChange", references: ["0", "0", "0", "1"])).value == "one")
        #expect(try session.request(get("OnSecondChange", references: ["0", "0", "0", "1"])).value == "two")
    }
    @Test func visibilityStrokeCommunicateAndSurfaceDerivedEvents() throws {
        let names = ["Mae.MikireBegin", "Mae.Mikire", "Mae.MikireEnd", "Mae.KasanariBegin", "Mae.Kasanari", "Mae.KasanariEnd", "Mae.SawariSakura.head", "Mae.SawariKero.hand", "Mae.ResponseFollow", "Mae.ResponseAgainst", "Mae.OnSurfaceRestoreSakura.5"]
        let root = try fixture(names.map { "#\($0)\n\($0)" }.joined(separator: "\n"), files: ["mae.ini": "TALK_INTERVAL=0\nMIKIRE=2\nKASANARI=2\nSAWARI=2", "words.dic": "(品詞 (名詞 一般)) ((見出し語 (嫌い 100))) (ジャンル 一般) (タイトル 一般) (価値観 -3)"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try MaeSession(masterDirectoryURL: root)
        func second(_ clip: String, _ overlap: String) throws -> String? {
            try session.request(get("OnSecondChange", references: ["0", clip, overlap, "1"])).value
        }
        #expect(try second("0", "0") == nil)
        #expect(try second("1", "0") == "Mae.MikireBegin")
        #expect(try second("1", "0") == "Mae.Mikire")
        #expect(try second("1", "0") == nil)
        #expect(try second("0", "0") == "Mae.MikireEnd")
        #expect(try second("0", "1") == "Mae.KasanariBegin")
        #expect(try second("0", "1") == "Mae.Kasanari")
        #expect(try second("0", "0") == "Mae.KasanariEnd")
        for scope in ["0", "1"] {
            let part = scope == "0" ? "head" : "hand"
            #expect(try session.request(get("OnMouseMove", references: ["0", "0", "0", scope, part])).value == nil)
            #expect(try session.request(get("OnMouseMove", references: ["3", "0", "0", scope, part])).value == nil)
            #expect(try session.request(get("OnMouseMove", references: ["6", "0", "0", scope, part])).value == "Mae.Sawari\(scope == "0" ? "Sakura" : "Kero").\(part)")
        }
        #expect(try session.request(get("OnCommunicate", references: ["user", "hello"])).value == "Mae.ResponseFollow")
        #expect(try session.request(get("OnCommunicate", references: ["user", "嫌い"])).value == "Mae.ResponseAgainst")
        #expect(try session.request(get("OnSurfaceRestore", references: ["5", "10"])).value == "Mae.OnSurfaceRestoreSakura.5")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MAE_LOCAL_GHOST"] != nil))
    func optionalLocalGhostLoadsWithoutModifyingIt() throws {
        guard let path = ProcessInfo.processInfo.environment["MAE_LOCAL_GHOST"] else { return }
        let state = FileManager.default.temporaryDirectory.appending(path: "mae-local-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: state) }
        let session = try MaeSession(masterDirectoryURL: URL(fileURLWithPath: path), stateStoreURL: state)
        let response = try session.request(get("OnBoot"))
        #expect(response.statusCode == 200)
        #expect(response.value?.isEmpty == false)
        try session.close()
    }
}
