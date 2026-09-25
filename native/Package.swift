// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UtataneModules",
    platforms: [.macOS(.v14)],
    products: [.library(name: "misaka", type: .dynamic, targets: ["MisakaModule"]),
        .library(name: "niseshiori", type: .dynamic, targets: ["NiseShioriModule"]),
        .library(name: "saori_cpuid", type: .dynamic, targets: ["SaoriCPUIDModule"]),
        .library(name: "kenonoke", type: .dynamic, targets: ["KenonokeModule"]),
        .library(name: "textcopy2", type: .dynamic, targets: ["TextCopyModule"]),
        .library(name: "mciaudior", type: .dynamic, targets: ["MciAudioModule"]),
        .library(name: "wmove", type: .dynamic, targets: ["WmoveModule"])],
    targets: [
        .target(name: "CMisakaHostBridge", path: "bridge", exclude: ["tests"], sources: ["anchor.c"], publicHeadersPath: "include"),
        .target(name: "ModuleProtocol"),
        .target(name: "LegacyTextCodec", path: "Sources/LegacyTextCodec", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("iconv")]),
        .target(name: "LegacyText", dependencies: ["LegacyTextCodec"]),
        .target(name: "NiseShioriCore", dependencies: ["ModuleProtocol", "LegacyText"]),
        .target(name: "NiseShioriModule", dependencies: ["NiseShioriCore", "ModuleProtocol", "LegacyText"]),
        .testTarget(name: "NiseShioriCoreTests", dependencies: ["NiseShioriCore", "ModuleProtocol"]),
        .target(name: "SaoriCore"),
        .target(name: "SaoriRuntime", dependencies: ["SaoriCore"]),
        .target(name: "SaoriCPUIDModule", dependencies: ["SaoriRuntime"]),
        .target(name: "KenonokeModule", dependencies: ["SaoriRuntime"]),
        .target(name: "TextCopyModule", dependencies: ["SaoriRuntime"]),
        .target(name: "MciAudioModule", dependencies: ["SaoriRuntime"]),
        .target(name: "WmoveModule", dependencies: ["SaoriRuntime"]),
        .testTarget(name: "SaoriTests", dependencies: ["SaoriCore", "SaoriRuntime"]),
        .target(name: "MisakaCore", dependencies: ["ModuleProtocol"]),
        .target(name: "MisakaModule", dependencies: ["MisakaCore", "ModuleProtocol", "CMisakaHostBridge"]),
        .testTarget(name: "MisakaCoreTests", dependencies: ["MisakaCore", "ModuleProtocol"])
    ]
)
