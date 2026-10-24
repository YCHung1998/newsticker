import Foundation

enum TestSupport {
    /// 以 #filePath 往上尋找含 protocol/fixtures/manifest.json 的倉庫根目錄。找不到就回報失敗（不略過）。
    static func repoRoot(from file: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("protocol/fixtures/manifest.json").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
