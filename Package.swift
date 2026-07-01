// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MarkOff",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MarkOffApp", targets: ["MarkOffApp"]),
    ],
    targets: [
        .executableTarget(
            name: "MarkOffApp",
            path: "Sources/MarkOffApp",
            resources: [
                .copy("../../Scripts"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
        .testTarget(
            name: "MarkOffAppTests",
            dependencies: ["MarkOffApp"],
            path: "Tests/MarkOffAppTests"
        ),
    ]
)
