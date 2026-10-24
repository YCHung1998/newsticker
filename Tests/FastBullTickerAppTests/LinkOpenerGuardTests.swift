import Testing
import Foundation

/// 守衛（比照 ticker-connect 的 `no_external_network`）：
/// - `Tests/` 原始碼不得出現真實開啟連結的呼叫；
/// - `Sources/` 只有 `Workspace*Opener.swift` 可以出現；
/// - `Sources/` 不得有啟用本 App 的呼叫。
/// 守衛本身以拼接組出被禁字串，避免掃到自己；掃描函式另以暫存目錄植入違規來證明守衛會失敗。
enum OpenerGuard {
    static let forbidden = ["NSWorkspace", ".shared", ".open"].joined()
    static let activationPatterns = ["NSApp.activate", "NSApplication.shared.activate", "activate(ignoringOtherApps"]

    static func swiftFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    static func isAllowedOpenerFile(_ url: URL) -> Bool {
        let n = url.lastPathComponent
        return n.hasPrefix("Workspace") && n.hasSuffix("Opener.swift")
    }

    /// 回傳違規檔案的相對描述。
    static func violations(root: URL) -> [String] {
        var out: [String] = []
        for f in swiftFiles(under: root.appendingPathComponent("Tests")) {
            if let s = try? String(contentsOf: f, encoding: .utf8), s.contains(forbidden) { out.append("Tests: \(f.lastPathComponent)") }
        }
        for f in swiftFiles(under: root.appendingPathComponent("Sources")) {
            guard let s = try? String(contentsOf: f, encoding: .utf8) else { continue }
            if s.contains(forbidden), !isAllowedOpenerFile(f) { out.append("Sources: \(f.lastPathComponent)") }
        }
        return out
    }

    /// single-instance 的唯一例外檔（重複實例對話框必須把 accessory App 帶到前景）。
    static let activationExceptionFile = "SingleInstanceGuard.swift"

    /// 各檔案（去掉整行註解後）出現啟用呼叫的次數。
    static func activationHitCounts(root: URL) -> [String: Int] {
        var out: [String: Int] = [:]
        for f in swiftFiles(under: root.appendingPathComponent("Sources")) {
            guard let raw = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let s = raw.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            let n = activationPatterns.reduce(0) { $0 + s.components(separatedBy: $1).count - 1 }
            if n > 0 { out[f.lastPathComponent] = n }
        }
        return out
    }

    /// 違規：例外檔以外任何啟用呼叫；例外檔內超過一處。
    static func activationViolations(root: URL) -> [String] {
        activationHitCounts(root: root).compactMap { name, n in
            if name != activationExceptionFile { return name }
            return n > 1 ? "\(name) (超過一處)" : nil
        }.sorted()
    }

    static func repoRoot(from file: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

@Suite struct LinkOpenerGuardTests {
    private func scratch() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("opener-guard-\(UUID().uuidString)")
        for sub in ["Tests", "Sources"] { try FileManager.default.createDirectory(at: d.appendingPathComponent(sub), withIntermediateDirectories: true) }
        return d
    }

    @Test func realTreeIsClean() throws {
        let root = try #require(OpenerGuard.repoRoot(), "找不到倉庫根目錄（Package.swift）")
        #expect(OpenerGuard.violations(root: root).isEmpty, "\(OpenerGuard.violations(root: root))")
        #expect(OpenerGuard.activationViolations(root: root).isEmpty, "\(OpenerGuard.activationViolations(root: root))")
        #expect(!OpenerGuard.swiftFiles(under: root.appendingPathComponent("Tests")).isEmpty, "掃描範圍不得為空")
    }

    @Test func plantedViolationInTestsFails() throws {
        let d = try scratch(); defer { try? FileManager.default.removeItem(at: d) }
        try "func f() { _ = \(OpenerGuard.forbidden)(URL(string: \"https://x.test\")!) }".write(to: d.appendingPathComponent("Tests/Bad.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.violations(root: d) == ["Tests: Bad.swift"])
    }

    @Test func sourcesAllowedOnlyInWorkspaceOpenerFiles() throws {
        let d = try scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let code = "func f() { _ = \(OpenerGuard.forbidden)(u) }"
        try code.write(to: d.appendingPathComponent("Sources/WorkspaceURLOpener.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.violations(root: d).isEmpty)
        try code.write(to: d.appendingPathComponent("Sources/AppDelegate.swift"), atomically: true, encoding: .utf8)
        try code.write(to: d.appendingPathComponent("Sources/WorkspaceHelper.swift"), atomically: true, encoding: .utf8)
        #expect(Set(OpenerGuard.violations(root: d)) == ["Sources: AppDelegate.swift", "Sources: WorkspaceHelper.swift"])
    }

    @Test func plantedActivationCallIsDetected() throws {
        let d = try scratch(); defer { try? FileManager.default.removeItem(at: d) }
        try "func f() { NSApp.activate(ignoringOtherApps: true) }".write(to: d.appendingPathComponent("Sources/X.swift"), atomically: true, encoding: .utf8)
        #expect(OpenerGuard.activationViolations(root: d) == ["X.swift"])
    }
}
