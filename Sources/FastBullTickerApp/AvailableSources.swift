import Foundation

/// 以 helper 的 `--list-sources` 取得「真的有連接器」的來源 id（change source-switcher：單一事實來源）。
public enum AvailableSources {
    /// 取不到清單時只認預設來源。
    public static let fallback: Set<String> = [SourceRegistry.fallbackID]

    /// 同步執行 `helper --list-sources`，逾時（預設 5 秒）就終止子行程。失敗、逾時、沒有任何合法 id 一律回傳 nil。
    /// 輸出每行一個 id；不合法的行（空白、大寫等）被丟棄。
    public static func fetch(helper: URL, timeout: TimeInterval = 5) -> Set<String>? {
        let p = Process()
        p.executableURL = helper
        p.arguments = ["--list-sources"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        // 先讀輸出再等結束，避免輸出填滿管道造成互等；清單很短，讀到 EOF 即可。
        var data = Data()
        let reader = DispatchQueue(label: "available-sources.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); readDone.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            _ = readDone.wait(timeout: .now() + 1)
            return nil
        }
        _ = readDone.wait(timeout: .now() + 1)
        guard p.terminationStatus == 0 else { return nil }
        let ids = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { SourceRegistry.isValidID($0) }
        return ids.isEmpty ? nil : Set(ids)
    }
}
