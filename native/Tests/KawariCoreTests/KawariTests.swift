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
    #expect(try session.request(request).value?.contains("起動") == true)
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
