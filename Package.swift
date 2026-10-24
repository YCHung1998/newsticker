// swift-tools-version: 6.0
// 【假設】Package.swift 放倉庫根目錄、最低 macOS 14、Core 使用 Swift 6 語言模式（tools-version 6.0 預設）。
import PackageDescription

let package = Package(
    name: "FastBullTicker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FastBullTickerCore", targets: ["FastBullTickerCore"]),
        .library(name: "FastBullTickerApp", targets: ["FastBullTickerApp"]),
        .executable(name: "FastBullTicker", targets: ["FastBullTicker"]),
    ],
    targets: [
        // 純邏輯，不得 import AppKit/SwiftUI/QuartzCore/Cocoa/UIKit（由 PackageSkeletonTests 強制）。
        .target(name: "FastBullTickerCore"),
        // App 側 library（可用 Foundation／AppKit）：FeedClient 等，供測試。2026-10-24（app-shell 2.x）。
        .target(name: "FastBullTickerApp", dependencies: ["FastBullTickerCore"]),
        // 空殼；UI 屬 app-shell 第 B 段（3.x／4.x）。
        .executableTarget(name: "FastBullTicker", dependencies: ["FastBullTickerCore", "FastBullTickerApp"]),
        .testTarget(name: "FastBullTickerCoreTests", dependencies: ["FastBullTickerCore"]),
        .testTarget(name: "FastBullTickerAppTests", dependencies: ["FastBullTickerApp", "FastBullTickerCore"]),
    ]
)
