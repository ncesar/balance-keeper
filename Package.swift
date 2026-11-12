// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BalanceKeeper",
    platforms: [.macOS("14.4")],
    targets: [.executableTarget(name: "BalanceKeeper")]
)
