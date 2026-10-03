// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Headroom", targets: ["Headroom"]),
        .executable(name: "headroom-probe", targets: ["headroom-probe"]),
    ],
    targets: [
        // Plain C so the same probe can back the Flutter plugin later. No unsafe
        // flags: a package that needs them cannot be consumed as a dependency, so
        // the triad's vector loop is written with NEON intrinsics rather than
        // left to the optimiser, and the target reports when it was built
        // without one (a debug build spills that loop to the stack).
        .target(name: "CHeadroom"),
        .target(
            name: "Headroom",
            dependencies: ["CHeadroom"],
            resources: [.copy("Resources/calibration.json")]
        ),
        .executableTarget(
            name: "headroom-probe",
            dependencies: ["Headroom"],
            path: "Executables/headroom-probe"
        ),
        .testTarget(name: "HeadroomTests", dependencies: ["Headroom"]),
    ]
)
