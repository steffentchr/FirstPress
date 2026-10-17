// swift-tools-version: 6.0
import PackageDescription

// FirstPressCore holds all of First Press's behaviour. It must not import UIKit or
// SwiftUI: the app target is a thin shell over it, and `swift test` runs it on
// macOS without a simulator.
//
// FirstPressMenuCore is First Press Menu's model: its connection states and what
// its panel shows. It shares the wire types with FirstPressCore and, like it,
// imports only Foundation and Observation.
let package = Package(
    name: "FirstPressCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FirstPressCore", targets: ["FirstPressCore"]),
        .library(name: "FirstPressMenuCore", targets: ["FirstPressMenuCore"]),
    ],
    targets: [
        .target(name: "FirstPressCore"),
        .target(name: "FirstPressMenuCore", dependencies: ["FirstPressCore"]),
        .testTarget(name: "FirstPressCoreTests", dependencies: ["FirstPressCore", "FirstPressMenuCore"]),
    ]
)
