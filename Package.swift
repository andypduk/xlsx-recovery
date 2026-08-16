// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XLSXRescue",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "xlsx-rescue", targets: ["XLSXRescueCLI"]),
        .library(name: "OfficeCrypto", targets: ["OfficeCrypto"]),
        .library(name: "Recovery", targets: ["Recovery"]),
    ],
    targets: [
        .target(name: "OfficeCrypto"),
        .target(
            name: "Recovery",
            dependencies: ["OfficeCrypto"]
        ),
        .executableTarget(
            name: "XLSXRescueCLI",
            dependencies: ["OfficeCrypto"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["XLSXRescueCLI", "OfficeCrypto"]
        ),
        .testTarget(
            name: "OfficeCryptoTests",
            dependencies: ["OfficeCrypto"]
        ),
        .testTarget(
            name: "RecoveryTests",
            dependencies: ["Recovery", "OfficeCrypto"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
