// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalFinanceApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PersonalFinanceApp", targets: ["PersonalFinanceApp"])
    ],
    targets: [
        .executableTarget(name: "PersonalFinanceApp")
    ]
)
