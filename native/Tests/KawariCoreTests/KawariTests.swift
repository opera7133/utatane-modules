import Foundation
import ModuleProtocol
import Testing
@testable import KawariCore

@Test func fileEventsUseWindowsSeparatorsAndOpenAbsolutePaths() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "kawari-path-ソング🎵-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appending(path: "テスト ソング🎵.txt")
    try #require("readable".data(using: .shiftJIS)).write(to: file)
    try #require(#"""
    System.Callback.OnGET : $(entry ${System.Request.ID};)
    OnFileDropEx : $(setstr testpath ${System.Request.Reference0}; entry TestPath;)
    OnPlaylistImport : $(setstr testpath ${System.Request.Reference2}; entry TestPath;)
    TestPath : $(
        clear @parts;
        split @parts $(rsub ${testpath} \ "<>") "<>";
        textload @data ${testpath};
        echo $(isexist ${testpath}) "|" $@parts[1] "|" ${@data};
    )
    """#.data(using: .shiftJIS)).write(to: root.appending(path: "kawarirc.kis"))
    let session = try KawariSession(masterDirectoryURL: root)
    for (id, references) in [
        ("OnFileDropEx", [0: file.path, 1: "1"]),
        ("OnFileDropEx", [0: file.path.decomposedStringWithCanonicalMapping, 1: "1"]),
        ("OnPlaylistImport", [0: "open", 1: "OnPlaylistImport", 2: file.path])
    ] {
        let request = ShioriRequest(method: "GET", headers: .init(
            [.init(name: "ID", value: id)] + references.sorted { $0.key < $1.key }.map {
                .init(name: "Reference\($0.key)", value: $0.value)
            }
        ))
        let value = try #require(session.request(request).value)
        #expect(value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == ["1", "テスト ソング🎵.txt", "readable"])
    }
    let ordinary = ShioriRequest(method: "GET", headers: .init([
        .init(name: "ID", value: "OnChoiceSelect"), .init(name: "Reference0", value: file.path)
    ]))
    #expect(KawariSession.filePathCompatibleRequest(ordinary) == ordinary)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["KAWARI_CLDSP_TEST_MASTER"] != nil))
func cldspImportsSelectedAndDroppedAudioIntoItsPlaylist() throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["KAWARI_CLDSP_TEST_MASTER"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "kawari-cldsp-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)
    let config = master.appending(path: "kawarirc.kis")
    let snapshot = #"""

    OnUtataneTestPlaylist : $(echo $(size playlist.p) "|" $playlist.f[$[ $(size playlist.p)-1 ]];)
    OnUtataneTestImportProgress : $(echo ${getid3end} "|" ${getid3tag} "|" $playlist.l[$[ $(size playlist.p)-1 ]];)
    """#
    let handle = try FileHandle(forWritingTo: config)
    try handle.seekToEnd()
    try handle.write(contentsOf: #require(snapshot.data(using: .shiftJIS)))
    try handle.close()
    let session = try KawariSession(masterDirectoryURL: master)
    func request(_ id: String, _ references: [Int: String] = [:]) throws -> ShioriResponse {
        try session.request(ShioriRequest(method: "GET", headers: .init(
            [.init(name: "ID", value: id)] + references.sorted { $0.key < $1.key }.map {
                .init(name: "Reference\($0.key)", value: $0.value)
            }
        )))
    }
    // Test a copy, including the source ghost's own importer. No original saves are written.
    let before = try #require(request("OnUtataneTestPlaylist").value)
    let initialCount = try #require(Int(before.components(separatedBy: "|")[0].trimmingCharacters(in: .whitespacesAndNewlines)))
    let realAudio = ProcessInfo.processInfo.environment["KAWARI_TEST_AUDIO_PATH"].map { URL(fileURLWithPath: $0) }
    let selected = realAudio ?? root.appending(path: "選択 ソング.mp3")
    let dropped = realAudio ?? root.appending(path: "ドロップ ソング.mp3")
    if realAudio == nil { for file in [selected, dropped] { try Data().write(to: file) } }
    _ = try request("OnPlaylistImport", [0: "open", 1: "OnPlaylistImport", 2: selected.path])
    let selectedResult = try #require(request("OnUtataneTestPlaylist").value)
    #expect(selectedResult.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == [String(initialCount + 1), selected.lastPathComponent])
    _ = try request("OnFileDropEx", [0: dropped.path, 1: "1"])
    let droppedResult = try #require(request("OnUtataneTestPlaylist").value)
    #expect(droppedResult.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == [String(initialCount + 2), dropped.lastPathComponent])
    if realAudio != nil {
        for _ in 0 ..< 5 { _ = try request("OnSecondChange", [3: "1"]) }
        let progress = try #require(request("OnUtataneTestImportProgress").value)
        let values = progress.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(values[0] == "0")
        #expect(values[1] == "0")
        #expect(try request("OnUtataneTestPlaylist").value == droppedResult)
    }
}

@Test func legacyDictionaryAnswersBoot() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "kawari-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try #require("dict : events.txt\r\n".data(using: .shiftJIS))
        .write(to: root.appending(path: "kawari.ini"))
    try #require("event.OnBoot : \\0起動\\e\r\n".data(using: .shiftJIS))
        .write(to: root.appending(path: "events.txt"))
    let session = try KawariSession(masterDirectoryURL: root)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    let response = try session.request(request)
    #expect(response.value?.contains("起動") == true, Comment(rawValue: response.serialized()))
    let notification = ShioriRequest(method: "NOTIFY", headers: .init([
        .init(name: "ID", value: "installedkeroname"),
        .init(name: "Reference0", value: "우뉴")
    ]))
    #expect(try session.request(notification).statusCode == 200)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["KAWARI_TEST_MASTER"] != nil))
func installedGhostDictionaryLoads() throws {
    let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["KAWARI_TEST_MASTER"]))
    let master = FileManager.default.temporaryDirectory.appending(path: "kawari-ghost-\(UUID())")
    defer { try? FileManager.default.removeItem(at: master) }
    try FileManager.default.copyItem(at: source, to: master)
    let session = try KawariSession(masterDirectoryURL: master)
    let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")]))
    #expect((200 ..< 300).contains(try session.request(request).statusCode))
}

@Test func unicodeDictionaryRegexAndLambda() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "華和梨😀-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let dictionary = #"""
    System.Callback.OnGET: ${event.${System.Request.ID}}
    event.OnBoot: \0日本語😀\e
    event.OnRegex: $(regex_replace "あ1い2" "[0-9]" "X")
    event.OnLambda: $(set f $(lambda $(echo [$@arg[1]])))$(${f} hi)
    """#
    try Data(([0xef, 0xbb, 0xbf] as [UInt8]) + Array(dictionary.utf8))
        .write(to: root.appending(path: "kawarirc.kis"))
    let session = try KawariSession(masterDirectoryURL: root)
    for (event, expected) in [("OnBoot", "日本語😀"), ("OnRegex", "あXいX"), ("OnLambda", "[hi]")] {
        let request = ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: event)]))
        let response = try session.request(request)
        #expect(response.value?.contains(expected) == true, Comment(rawValue: response.serialized()))
    }
}

@Test(arguments: ["httpc", "saori_cpuid"])
func nativeSaoriTakesPrecedenceOverCompatibilityNameFallback(_ name: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "kawari-saori-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = root.appending(path: "echo.c")
    try #"""
    #include <stdint.h>
    #include <stdlib.h>
    #include <string.h>
    int32_t loadu(void *p, int32_t n) { free(p); return n > 0; }
    int32_t unload(void) { return 1; }
    void *request(void *p, int32_t *n) {
        int execute = *n >= 8 && memcmp(p, "EXECUTE ", 8) == 0;
        free(p);
        const char *reply = execute ? "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\nResult: native-ok\r\n\r\n"
                                    : "SAORI/1.0 200 OK\r\nCharset: UTF-8\r\n\r\n";
        *n = (int32_t)strlen(reply); void *out = malloc(*n); memcpy(out, reply, *n); return out;
    }
    """#.write(to: fixture, atomically: true, encoding: .utf8)
    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
    compiler.arguments = ["clang", "-dynamiclib", fixture.path, "-o", root.appending(path: "lib\(name).dylib").path]
    try compiler.run(); compiler.waitUntilExit()
    try #require(compiler.terminationStatus == 0)
    try "System.Callback.OnGET: ${event.${System.Request.ID}}\nevent.OnBoot: $(saoriregist \(name).dll native)$(callsaori native)\n".write(to: root.appending(path: "kawarirc.kis"), atomically: true, encoding: .utf8)
    let session = try KawariSession(masterDirectoryURL: root)
    let response = try session.request(ShioriRequest(method: "GET", headers: .init([.init(name: "ID", value: "OnBoot")])))
    #expect(response.value == "native-ok")
}
