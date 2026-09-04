// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "verification",
    products: [
        .library(name: "LogicCore", targets: ["LogicCore"])
    ],
    targets: [
        .target(name: "LogicCore"),
        .testTarget(name: "LogicCoreTests", dependencies: ["LogicCore"])
    ]
)
