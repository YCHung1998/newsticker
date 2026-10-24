// swift-tools-version: 5.9
// 丟棄式可行性實驗（change: panel-feasibility-spikes）。獨立於根目錄 Package.swift，不得被正式專案引用。
import PackageDescription

let package = Package(
    name: "spikes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spike-s1", targets: ["SpikeS1"]),
        .executable(name: "spike-focus", targets: ["SpikeFocus"]),
        .executable(name: "spike-s3", targets: ["SpikeS3"]),
        .executable(name: "spike-render", targets: ["SpikeRender"]),
    ],
    targets: [
        .target(name: "SpikeKit"),
        .executableTarget(name: "SpikeS1", dependencies: ["SpikeKit"]),
        .executableTarget(name: "SpikeFocus", dependencies: ["SpikeKit"]),
        .executableTarget(name: "SpikeS3", dependencies: ["SpikeKit"]),
        .executableTarget(name: "SpikeRender", dependencies: ["SpikeKit"]),
    ]
)
