// swift-tools-version: 6.0
import PackageDescription

// PressingCore holds all of Pressing's behaviour. It must not import UIKit or
// SwiftUI: the app target is a thin shell over it, and `swift test` runs it on
// macOS without a simulator.
//
// PressingMenuCore is Pressing Menu's model: its connection states and what
// its panel shows. It shares the wire types with PressingCore and, like it,
// imports only Foundation and Observation.
let package = Package(
    name: "PressingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PressingCore", targets: ["PressingCore"]),
        .library(name: "PressingMenuCore", targets: ["PressingMenuCore"]),
    ],
    targets: [
        .target(name: "PressingCore"),
        .target(name: "PressingMenuCore", dependencies: ["PressingCore"]),
        .testTarget(name: "PressingCoreTests", dependencies: ["PressingCore", "PressingMenuCore"]),
    ]
)
