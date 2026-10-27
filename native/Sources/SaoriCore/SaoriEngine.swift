import Foundation

public enum SaoriKind: String, CaseIterable, Sendable {
    case cpuid = "saori-cpuid"
    case kenonoke
    case httpc
    case clipcopy
    case textcopy
    case saoriIP = "saori-ip"
    case textcopy2
    case mciaudior
    case proxyEx = "proxy_ex"
    case wmove
    case playwavsound
    case totpSaori = "totp-saori"
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
        case .httpc: module = NativeHttpc(directory: directoryURL)
        case .textcopy2, .textcopy: module = NativeClipboardCompatibility(clipcopy: false, handler: textCopyHandler)
        case .clipcopy: module = NativeClipboardCompatibility(clipcopy: true, handler: textCopyHandler)
        case .saoriIP: module = NativeIPCompatibility()
        case .mciaudior: module = NativeMciAudioR(baseDirectoryURL: directoryURL)
        case .proxyEx: module = NativeProxyEx(baseDirectoryURL: directoryURL)
        case .wmove: module = NativeWmove(windowController: windowController)
        case .playwavsound: module = NativePlayWavSound(directory: directoryURL)
        case .totpSaori: module = NativeTOTP()
        }
    }

    public func call(_ arguments: [String]) -> [String] {
        if let httpc = module as? NativeHttpc { return httpc.callValues(arguments) }
        return module.call(arguments).components(separatedBy: "\u{1}")
    }

    public func execute(_ arguments: [String]) -> SaoriExecution {
        if let clipboard = module as? NativeClipboardCompatibility { return clipboard.execute(arguments) }
        if let ip = module as? NativeIPCompatibility { return ip.execute(arguments) }
        if let wave = module as? NativePlayWavSound { return wave.execute(arguments) }
        if let totp = module as? NativeTOTP { return totp.execute(arguments) }
        let values = call(arguments)
        return .init(values.allSatisfy(\.isEmpty) ? 204 : 200, values)
    }

    public func unload() {
        module.unload()
    }

    deinit { module.unload() }
}
