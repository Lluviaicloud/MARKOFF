// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "InpaintVideos",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "InpaintVideosApp", targets: ["InpaintVideosApp"]),
    ],
    targets: [
        .executableTarget(
            name: "InpaintVideosApp",
            path: "Sources/InpaintVideosApp",
            resources: [
                .copy("../../Scripts"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
        .testTarget(
            name: "InpaintVideosAppTests",
            dependencies: ["InpaintVideosApp"],
            path: "Tests/InpaintVideosAppTests"
        ),
    ]
)
