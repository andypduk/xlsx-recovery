// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XLSXRescue",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "xlsx-rescue", targets: ["XLSXRescueCLI"]),
        .library(name: "OfficeCrypto", targets: ["OfficeCrypto"]),
    ],
    targets: [
        .target(name: "OfficeCrypto"),
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
    ],
    swiftLanguageModes: [.v6]
)
