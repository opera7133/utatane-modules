import Foundation
import ModuleProtocol
import Testing

@Test func `shared state directory takes precedence and keeps the module filename`() throws {
    let result = try ModuleEnvironment.stateFile(
        named: "nise-shiori-state.json", legacyEnvironmentKey: "NISESHIORI_STATE_PATH",
        environment: [
            "UTATANE_GHOST_STATE_DIR": "/state/ghost",
            "NISESHIORI_STATE_PATH": "/legacy/state.json"
        ]
    )
    #expect(result?.path == "/state/ghost/nise-shiori-state.json")
}

@Test func `standalone hosts may omit the shared state directory`() throws {
    #expect(try ModuleEnvironment.stateFile(named: "state.json", legacyEnvironmentKey: "LEGACY",
                                            environment: [:]) == nil)
    #expect(try ModuleEnvironment.stateFile(named: "state.json", legacyEnvironmentKey: "LEGACY",
                                            environment: ["LEGACY": "/old/state.json"])?.path == "/old/state.json")
}

@Test func `invalid shared state directory is rejected`() {
    #expect(throws: ModuleEnvironment.PathError.self) {
        try ModuleEnvironment.stateFile(named: "state.json", legacyEnvironmentKey: "LEGACY",
                                        environment: ["UTATANE_GHOST_STATE_DIR": "../relative"])
    }
}
