// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalFinanceApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PersonalFinanceApp", targets: ["PersonalFinanceApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .executableTarget(
            name: "PersonalFinanceApp",
            dependencies: ["CSQLite"]
        )
    ]
)
