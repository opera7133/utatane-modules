import Foundation

public enum SaoriKind: String, CaseIterable, Sendable {
    case cpuid = "saori-cpuid"
    case kenonoke
    case textcopy2
    case mciaudior
    case wmove
}

/// One loaded SAORI. The caller serializes requests and unload.
public final class SaoriEngine {
    private let module: any NativeSaoriModule

    public init(kind: SaoriKind, directoryURL: URL,
                windowController: (any NativeSaoriWindowControlling)? = nil,
                textCopyHandler: (@Sendable (String) -> Void)? = nil)
    {
        switch kind {
        case .cpuid: module = NativeSystemInfo()
        case .kenonoke: module = NativeKeyword(moduleURL: directoryURL.appending(path: "libkenonoke.dylib"))
        case .textcopy2: module = NativeTextCopy(pasteboardName: nil, handler: textCopyHandler)
        case .mciaudior: module = NativeMciAudioR(baseDirectoryURL: directoryURL)
        case .wmove: module = NativeWmove(windowController: windowController)
        }
    }

    public func call(_ arguments: [String]) -> [String] {
        module.call(arguments).components(separatedBy: "\u{1}")
    }

    public func unload() {
        module.unload()
    }

    deinit { module.unload() }
}
