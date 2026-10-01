// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "IperfSwift",
    products: [
        .library(
            name: "IperfSwift",
            targets: ["IperfCLib", "IperfSwift"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "IperfCLib",
            dependencies: [],
            path: "Sources/IperfCLib",
            cSettings: [
                // Upstream iperf3 mixes 64-bit and int types throughout; not worth patching vendored code.
                .unsafeFlags(["-Wno-shorten-64-to-32"])
            ]
        ),
        .target(
            name: "IperfSwift",
            dependencies: ["IperfCLib"],
            path: "Sources/IperfSwift"
        ),
        .testTarget(
            name: "iperf-swiftTests",
            dependencies: ["IperfSwift"]),
    ]
)
