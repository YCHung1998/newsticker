import Foundation
import Darwin

/// pid file：記錄目前 helper 的 pid 與路徑，供下次啟動時清理「上一個 App 被 kill -9 後遺留的 helper」。
/// 預設位置 `~/Library/Application Support/FastBullTicker/helper.pid`（【假設】）。
public struct PidFile: Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var pid: Int32
        public var helper: String
    }

    public let url: URL
    public init(url: URL) { self.url = url }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FastBullTicker/helper.pid")
    }

    public func read() -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public func write(pid: Int32, helper: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Record(pid: pid, helper: helper)) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 只有內容仍是 `pid` 時才刪除（避免刪到新一代寫的檔）。
    public func remove(ifPid pid: Int32) {
        if read()?.pid == pid { try? FileManager.default.removeItem(at: url) }
    }

    func removeUnconditionally() { try? FileManager.default.removeItem(at: url) }
}

enum ProcessInspector {
    static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// `ps -o ppid=,command= -p pid`；失敗回傳 nil。
    static func info(_ pid: Int32) -> (ppid: Int32, command: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "ppid=,command=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let ppid = Int32(parts[0]) else { return nil }
        return (ppid, String(parts[1]))
    }

    /// 終止舊 helper：SIGTERM，輪詢至 `timeout` 後仍活著則 SIGKILL。會阻塞呼叫端執行緒。
    static func terminate(_ pid: Int32, timeout: TimeInterval) {
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(timeout)
        while isAlive(pid) && !isZombie(pid) && Date() < deadline { usleep(20_000) }
        if isAlive(pid) && !isZombie(pid) { kill(pid, SIGKILL); usleep(50_000) }
    }

    private static func isZombie(_ pid: Int32) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "stat=", "-p", String(pid)]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z") ?? false
    }
}
