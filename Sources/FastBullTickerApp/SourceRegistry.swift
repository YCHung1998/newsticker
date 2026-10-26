import Foundation

/// 一筆來源：`id` 對應 helper（`ticker-connect --list-sources`）登錄的連接器，`name` 是選單顯示名稱，
/// `label` 是選填的左側標籤文字（有值時優先於 `style.json` 的 `labelText`）。
public struct SourceEntry: Equatable, Sendable {
    public var id: String
    public var name: String
    public var label: String?
    public init(id: String, name: String, label: String? = nil) { self.id = id; self.name = name; self.label = label }
}

/// `sources.json` 的記憶體模型（change source-switcher）。解析與驗證是純函式，檔案存取在 `SourceRegistryStore`。
public struct SourceRegistry: Equatable, Sendable {
    public var selected: String
    public var sources: [SourceEntry]
    public init(selected: String, sources: [SourceEntry]) { self.selected = selected; self.sources = sources }

    public static let fallbackID = "fastbull"
    public static let nameLength = 1...24
    public static let labelLength = StyleRanges.labelTextLength

    public static let `default` = SourceRegistry(selected: fallbackID, sources: [
        SourceEntry(id: "fastbull", name: "FastBull 快訊", label: "即時財經快訊"),
        SourceEntry(id: "jin10", name: "金十數據", label: "金十數據"),
    ])

    public enum ParseResult: Equatable, Sendable {
        case ok(SourceRegistry, warnings: [String])
        case invalid(String)
    }

    /// 與 helper 登錄表相同規則：小寫字母開頭、小寫英數與底線、2–32 字元。
    static func isValidID(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard (2...32).contains(u.count), (0x61...0x7A).contains(u[0]) else { return false }
        return u.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x5F }
    }

    public static func parse(_ data: Data) -> ParseResult {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .invalid("不是 JSON 物件") }
        var warnings: [String] = []
        for k in obj.keys.sorted() where !["version", "selected", "sources"].contains(k) { warnings.append("未知鍵 \(k) 已忽略") }
        guard let raw = obj["sources"] as? [Any] else { return .invalid("缺少 sources 陣列") }
        var seen = Set<String>(), out: [SourceEntry] = []
        for (i, el) in raw.enumerated() {
            guard let e = el as? [String: Any] else { warnings.append("sources[\(i)] 不是物件，已略過"); continue }
            for k in e.keys.sorted() where !["id", "name", "label"].contains(k) { warnings.append("sources[\(i)] 未知鍵 \(k) 已忽略") }
            guard let id = e["id"] as? String, isValidID(id) else { warnings.append("sources[\(i)] id 不合法，已略過"); continue }
            guard let rawName = e["name"] as? String, nameLength.contains(rawName.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
                warnings.append("來源 \(id) 的 name 缺少或長度不合法（1–24 字），已略過"); continue
            }
            guard seen.insert(id).inserted else { warnings.append("來源 \(id) 重複，只保留第一筆"); continue }
            var label: String?
            if let l = e["label"] {
                if let s = l as? String, labelLength.contains(s.trimmingCharacters(in: .whitespacesAndNewlines).count) {
                    label = s.trimmingCharacters(in: .whitespacesAndNewlines)
                } else { warnings.append("來源 \(id) 的 label 不合法（1–16 字），已忽略 label") }
            }
            out.append(SourceEntry(id: id, name: rawName.trimmingCharacters(in: .whitespacesAndNewlines), label: label))
        }
        guard !out.isEmpty else { return .invalid("沒有任何合法的來源") }
        return .ok(SourceRegistry(selected: (obj["selected"] as? String) ?? fallbackID, sources: out), warnings: warnings)
    }

    /// 啟動時實際使用的來源：`selected` 必須在清單內且 helper 有該連接器，否則退回 `fastbull`（不改檔案）。
    public func effectiveSelection(available: Set<String>) -> String {
        sources.contains { $0.id == selected } && available.contains(selected) ? selected : Self.fallbackID
    }

    public func entry(id: String) -> SourceEntry? { sources.first { $0.id == id } }

    func encoded() -> Data {
        var dict: [String: Any] = ["version": 1, "selected": selected]
        dict["sources"] = sources.map { s -> [String: Any] in
            var d: [String: Any] = ["id": s.id, "name": s.name]
            if let l = s.label { d["label"] = l }
            return d
        }
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}

/// `sources.json` 的讀寫：不存在就建立預設、損毀就備份並以預設取代、寫不進去時退回記憶體中的預設（不崩潰）。
public struct SourceRegistryStore: Sendable {
    public struct Loaded: Equatable, Sendable {
        public var registry: SourceRegistry
        public var warnings: [String]
        /// 要顯示在選單上的提示（目前只有「檔案損毀已重置」）。
        public var notice: String?
        public var writeError: String?
    }

    public let url: URL
    public init(url: URL) { self.url = url }

    /// 路徑可由 `FASTBULL_TICKER_SOURCES` 覆寫（測試與試用）。
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let p = environment["FASTBULL_TICKER_SOURCES"], !p.isEmpty { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FastBullTicker/sources.json")
    }

    private func writeAtomically(_ data: Data) -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return nil
        } catch { return "\(error)" }
    }

    public func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Loaded(registry: .default, warnings: [], notice: nil, writeError: writeAtomically(SourceRegistry.default.encoded()))
        }
        if let data = try? Data(contentsOf: url), case .ok(let reg, let w) = SourceRegistry.parse(data) {
            return Loaded(registry: reg, warnings: w, notice: nil, writeError: nil)
        }
        // 損毀（或讀不到）：先備份，再以預設取代，絕不靜默覆寫使用者的檔案。
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
        return Loaded(registry: .default, warnings: [], notice: "來源設定檔無法解讀，已備份為 sources.json.bak 並改用預設",
                      writeError: writeAtomically(SourceRegistry.default.encoded()))
    }

    /// 記住選擇：保留清單的順序、名稱與標籤，只改 `selected`。`id` 不在清單內或寫入失敗回傳 false。
    @discardableResult
    public func select(_ id: String) -> Bool {
        var reg = load().registry
        guard reg.sources.contains(where: { $0.id == id }) else { return false }
        reg.selected = id
        return writeAtomically(reg.encoded()) == nil
    }
}
