// swift-tools-version: 6.0
// 【假設】Package.swift 放倉庫根目錄、最低 macOS 14、Core 使用 Swift 6 語言模式（tools-version 6.0 預設）。
import PackageDescription

let package = Package(
    name: "FastBullTicker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FastBullTickerCore", targets: ["FastBullTickerCore"]),
        .executable(name: "FastBullTicker", targets: ["FastBullTicker"]),
    ],
    targets: [
        // 純邏輯，不得 import AppKit/SwiftUI/QuartzCore/Cocoa/UIKit（由 PackageSkeletonTests 強制）。
        .target(name: "FastBullTickerCore"),
        // 空殼；正式內容屬 app-shell change。
        .executableTarget(name: "FastBullTicker", dependencies: ["FastBullTickerCore"]),
        .testTarget(name: "FastBullTickerCoreTests", dependencies: ["FastBullTickerCore"]),
    ]
)
