// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clausage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Clausage",
            path: "Clausage",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClausageTests",
            dependencies: ["Clausage"],
            path: "Tests/ClausageTests"
        )
    ]
)
