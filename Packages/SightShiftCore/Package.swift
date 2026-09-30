// swift-tools-version: 5.10
import PackageDescription

// The camera-free half of SightShift: feature geometry, the gaze models, and the
// decision logic that turns noisy head-pose estimates into calm focus changes.
// Everything here is plain Swift so it can be unit-tested with `swift test`.
let package = Package(
    name: "SightShiftCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SightShiftCore", targets: ["SightShiftCore"]),
    ],
    targets: [
        .target(name: "SightShiftCore"),
        .testTarget(name: "SightShiftCoreTests", dependencies: ["SightShiftCore"]),
    ]
)
