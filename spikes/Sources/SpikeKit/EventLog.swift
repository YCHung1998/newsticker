import Foundation

/// 日誌格式：`<ISO8601 含毫秒與時區>\t<event>\t<k=v k=v ...>`（值內空白一律換成底線）。
public final class EventLog {
    public let path: String
    private let handle: FileHandle?
    private let lock = NSLock()
    private let fmt: DateFormatter

    public init(name: String, logFile: String?, logDir: String?) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"
        fmt = f
        let p: String
        if let lf = logFile {
            p = lf
        } else {
            let dir = logDir ?? "out"
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyyMMdd-HHmmss"
            p = "\(dir)/\(name)-\(stamp.string(from: Date())).log"
        }
        path = p
        let url = URL(fileURLWithPath: p)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: p) {
            FileManager.default.createFile(atPath: p, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    public func write(_ event: String, _ fields: [(String, String)] = []) {
        lock.lock(); defer { lock.unlock() }
        let kv = fields.map { "\($0.0)=\(EventLog.clean($0.1))" }.joined(separator: " ")
        let line = "\(fmt.string(from: Date()))\t\(event)\t\(kv)\n"
        if let d = line.data(using: .utf8) { try? handle?.write(contentsOf: d) }
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    static func clean(_ s: String) -> String {
        String(s.map { ($0 == " " || $0 == "\t" || $0 == "\n") ? "_" : $0 })
    }

    /// 單調時鐘（秒），供預定／實際觸發時間比較。
    public static func uptime() -> Double { ProcessInfo.processInfo.systemUptime }
    public static func f3(_ d: Double) -> String { String(format: "%.3f", d) }
}
