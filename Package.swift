// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XLSXRescue",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "xlsx-rescue", targets: ["XLSXRescueCLI"]),
        .library(name: "OfficeCrypto", targets: ["OfficeCrypto"]),
        .library(name: "Recovery", targets: ["Recovery"]),
        .library(name: "MetalVerifier", targets: ["MetalVerifier"]),
        .library(name: "OfficeContainer", targets: ["OfficeContainer"]),
    ],
    targets: [
        .target(name: "OfficeCrypto"),
        .target(
            name: "Recovery",
            dependencies: ["OfficeCrypto"]
        ),
        .target(name: "MetalVerifier", dependencies: ["OfficeCrypto", "Recovery"], resources: [.process("Office2013KDF.metal")]),
        .target(name: "OfficeContainer", dependencies: ["OfficeCrypto"]),
        .executableTarget(
            name: "XLSXRescueCLI",
            dependencies: ["OfficeCrypto", "Recovery", "MetalVerifier", "OfficeContainer"]
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
        .testTarget(name: "MetalVerifierTests", dependencies: ["MetalVerifier", "OfficeCrypto", "Recovery"]),
        .testTarget(name: "OfficeContainerTests", dependencies: ["OfficeContainer"]),
    ],
    swiftLanguageModes: [.v6]
)
