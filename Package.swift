// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MixBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MixBarEngine",
            path: "Sources/MixBarEngine",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("vendor"),
                .headerSearchPath("vendor/shared"),
                .headerSearchPath("vendor/PublicUtility"),
                .define("NDEBUG"),
                .define("CoreAudio_UseSysLog", to: "1"),
            ],
            cxxSettings: [
                .headerSearchPath("vendor"),
                .headerSearchPath("vendor/shared"),
                .headerSearchPath("vendor/PublicUtility"),
                .define("NDEBUG"),
                .define("CoreAudio_UseSysLog", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Foundation"),
                .linkedFramework("Accelerate"),
            ]
        ),
        .executableTarget(
            name: "MixBar",
            dependencies: ["MixBarEngine"],
            path: "Sources/MixBar"
        ),
        .executableTarget(
            name: "mixbarctl",
            dependencies: ["MixBarEngine"],
            path: "Sources/mixbarctl"
        ),
    ],
    cxxLanguageStandard: .gnucxx14
)
