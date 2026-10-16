// swift-tools-version: 6.0
import PackageDescription

// PressingCore holds all of Pressing's behaviour. It must not import UIKit or
// SwiftUI: the app target is a thin shell over it, and `swift test` runs it on
// macOS without a simulator.
let package = Package(
    name: "PressingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PressingCore", targets: ["PressingCore"]),
    ],
    targets: [
        .target(name: "PressingCore"),
        .testTarget(name: "PressingCoreTests", dependencies: ["PressingCore"]),
    ]
)
