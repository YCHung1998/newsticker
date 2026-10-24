import Testing
import Foundation
@testable import FastBullTickerCore

/// 掃描目錄下所有 .swift，回傳含被禁 import 的 "檔名:行號: 內容"。
func forbiddenImports(in directory: URL) -> [String] {
    let banned = ["AppKit", "SwiftUI", "QuartzCore", "Cocoa", "UIKit", "CoreAnimation"]
    let pattern = #"^\s*(@\w+\s+)*import\s+(\w+\s+)?("# + banned.joined(separator: "|") + #")\b"#
    let regex = try! NSRegularExpression(pattern: pattern)
    var hits: [String] = []
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { return ["<目錄不存在 \(directory.path)>"] }
    guard let en = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return ["<無法列舉 \(directory.path)>"] }
    for case let url as URL in en where url.pathExtension == "swift" {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let l = String(line)
            if regex.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil {
                hits.append("\(url.lastPathComponent):\(i + 1): \(l)")
            }
        }
    }
    return hits
}

@Suite struct PackageSkeletonTests {
    @Test func coreReportsProtocolVersion() {
        #expect(CoreInfo.supportedProtocolVersion == 1)
    }

    @Test func coreSourcesDoNotImportUIFrameworks() throws {
        let root = try #require(TestSupport.repoRoot(), "找不到倉庫根目錄（protocol/fixtures/manifest.json）")
        let hits = forbiddenImports(in: root.appendingPathComponent("Sources/FastBullTickerCore"))
        #expect(hits.isEmpty, "Core 出現被禁的 import: \(hits)")
    }

    @Test func importCheckerDetectsBannedImports() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("imp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for (i, line) in ["import AppKit", "  import SwiftUI", "@preconcurrency import QuartzCore", "import struct Cocoa.NSView", "import UIKit"].enumerated() {
            try (line + "\n").write(to: tmp.appendingPathComponent("f\(i).swift"), atomically: true, encoding: .utf8)
        }
        try "import Foundation\n// import AppKit (註解)\n".write(to: tmp.appendingPathComponent("ok.swift"), atomically: true, encoding: .utf8)
        #expect(forbiddenImports(in: tmp).count == 5)
    }

    @Test func checkerFailsOnMissingDirectory() {
        #expect(!forbiddenImports(in: URL(fileURLWithPath: "/nonexistent-dir-xyz")).isEmpty)
    }
}
