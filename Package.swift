// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StudyHelper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StudyHelper", path: "Sources/StudyHelper"),
        .testTarget(name: "StudyHelperTests", dependencies: ["StudyHelper"], path: "Tests/StudyHelperTests"),
    ]
)
