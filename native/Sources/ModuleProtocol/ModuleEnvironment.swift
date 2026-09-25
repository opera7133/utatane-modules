import Foundation

/// Host-provided locations are optional. Standalone SHIORI hosts may omit them.
public enum ModuleEnvironment {
    public enum PathError: Error { case invalidPath }

    public static func stateFile(named filename: String, legacyEnvironmentKey: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL? {
        if let root = environment["UTATANE_GHOST_STATE_DIR"] {
            guard root.hasPrefix("/"), !root.contains("\0") else { throw PathError.invalidPath }
            return URL(fileURLWithPath: root, isDirectory: true).appending(path: filename)
        }
        if let path = environment[legacyEnvironmentKey] {
            guard path.hasPrefix("/"), !path.contains("\0") else { throw PathError.invalidPath }
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
