import Foundation
@testable import MisakaCore
import ModuleProtocol
import Testing

private func request(_ id: String, reference: String? = nil) -> ShioriRequest {
    var headers = [ShioriHeader(name: "ID", value: id)]
    if let reference {
        headers.append(ShioriHeader(name: "Reference0", value: reference))
    }
    return ShioriRequest(method: "GET", headers: ShioriHeaders(headers))
}

private func withFixture(_ dictionary: String, _ body: (URL, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "日本語/master")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "dictionaries\n{\nmisaka.txt\n}\n".write(to: master.appending(path: "misaka.ini"), atomically: true, encoding: .shiftJIS)
    try dictionary.write(to: master.appending(path: "misaka.txt"), atomically: true, encoding: .shiftJIS)
    try body(master, root.appending(path: "state/variables.json"))
}

@Test("Japanese dictionary") func japaneseDictionary() throws {
    try withFixture("$_Variable\n{$username=\"ユーザ\"}\n\n$OnBoot\n起動。{$username}。") { master, state in
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        #expect(try session.request(request("OnBoot")).value == "起動。ユーザ。")
    }
}

@Test("Reference and sequential selection") func referenceAndSequentialSelection() throws {
    try withFixture("$OnChoiceSelect; {$if ({$reference(0)}==\"talk\")}\n{$_Talk}\n\n$_Talk; sequential;\nA\n\nB") { master, state in
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        #expect(try session.request(request("OnChoiceSelect", reference: "talk")).value == "A")
        #expect(try session.request(request("OnChoiceSelect", reference: "talk")).value == "B")
    }
}

@Test func arithmetic() throws {
    try withFixture("$OnBoot\n{$value=(1+2)*4}{$value}:{$calc(2^3^2)}") { master, state in
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        #expect(try session.request(request("OnBoot")).value == "12:512")
    }
}

@Test func nonoverlap() throws {
    try withFixture("$OnBoot; nonoverlap;\nA\n\nB\n\nC") { master, state in
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        let values = try (0 ..< 3).compactMap { _ in try session.request(request("OnBoot")).value }
        #expect(Set(values) == ["A", "B", "C"])
    }
}

@Test("Restore between defaults and constants") func restoreBetweenDefaultsAndConstants() throws {
    try withFixture("$_Variable\n{$saved=\"default\"}\n\n$_Constant\n{$constant=\"fresh\"}\n\n$OnBoot\n{$backup()}{$saved}:{$constant}") { master, state in
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["saved": ["restored"], "constant": ["stale"]]).write(to: state)
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        #expect(try session.request(request("OnBoot")).value == "restored:fresh")
        let saved = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: state))
        #expect(saved["constant"] == ["fresh"])
        #expect(!FileManager.default.fileExists(atPath: master.appending(path: "misaka_vars.json").path))
    }
}

@Test("Sessions are independent") func sessionsAreIndependent() throws {
    try withFixture("$_Variable\n{$count=0}\n\n$OnBoot\n{$count++}{$count}") { master, state in
        let first = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        let second = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state.appendingPathExtension("other"))
        #expect(try first.request(request("OnBoot")).value == "1")
        #expect(try first.request(request("OnBoot")).value == "2")
        #expect(try second.request(request("OnBoot")).value == "1")
    }
}

@Test("Missing configuration throws") func missingConfigurationThrows() throws {
    #expect(throws: NativeMisakaError.self) {
        try NativeMisakaSession(masterDirectoryURL: URL(fileURLWithPath: "/nonexistent-utatane-module-test"))
    }
}

@Test("Header only response") func headerOnlyResponse() throws {
    try withFixture("$OnResult\n{$appendheader(\"Reference0: result\")}") { master, state in
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        let result = try session.request(request("OnResult"))
        #expect(result.statusCode == 200)
        #expect(result.headers["Reference0"] == "result")
        let empty = try session.request(request("OnMissing"))
        #expect(empty.statusCode == 204)
        #expect(empty.headers["Reference0"] == nil)
    }
}
