// swift-tools-version: 5.9
// Portable Core builds on Linux (InnerTube fallback). Optional YouTubeKit when building on Apple OS in CI.
import PackageDescription

#if os(Linux) || os(Windows) || os(Android)
let youTubeKitPackage: [Package.Dependency] = []
let youTubeKitProducts: [Target.Dependency] = []
#else
let youTubeKitPackage: [Package.Dependency] = [
    .package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.8"),
]
let youTubeKitProducts: [Target.Dependency] = [
    .product(name: "YouTubeKit", package: "YouTubeKit"),
]
#endif

let package = Package(
    name: "FireballNative",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "FireballNativeCore", targets: ["FireballNativeCore"]),
    ],
    dependencies: youTubeKitPackage,
    targets: [
        .target(
            name: "FireballNativeCore",
            dependencies: youTubeKitProducts,
            path: "FireballNative/Core",
            exclude: [
                "NativeAudioEngine.swift",
            ]
        ),
        .testTarget(
            name: "FireballNativeCoreTests",
            dependencies: ["FireballNativeCore"]
        ),
    ]
)
