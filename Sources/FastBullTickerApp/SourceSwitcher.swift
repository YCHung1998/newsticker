import Foundation

/// 「來源」子選單的一行（純資料，便於測試）。
public struct SourceMenuItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case source(String), notice, separator, openFile }
    public var kind: Kind
    public var title: String
    public var checked: Bool
    public var enabled: Bool
}

public enum SourceMenuModel {
    /// 提示行（檔案損毀已重置）→ 依清單順序的來源（目前的打勾；helper 沒有連接器的停用並標註）→ 分隔線 → 「開啟來源設定檔…」。
    public static func items(registry: SourceRegistry, available: Set<String>, current: String, notice: String?) -> [SourceMenuItem] {
        var out: [SourceMenuItem] = []
        if let notice { out.append(SourceMenuItem(kind: .notice, title: notice, checked: false, enabled: false)) }
        for s in registry.sources {
            let ok = available.contains(s.id)
            out.append(SourceMenuItem(kind: .source(s.id), title: ok ? s.name : "\(s.name)（尚無連接器）", checked: s.id == current, enabled: ok))
        }
        out.append(SourceMenuItem(kind: .separator, title: "", checked: false, enabled: true))
        out.append(SourceMenuItem(kind: .openFile, title: "開啟來源設定檔…", checked: false, enabled: true))
        return out
    }
}

/// 來源切換流程（change source-switcher）。不直接碰視窗或行程：副作用都經 `Actions` 注入，所以可以完整單元測試。
/// 切換順序固定為：擋住舊訊息 → 清畫面 → 重啟 helper → 換標籤。
@MainActor
public final class SourceSwitcher {
    public struct Actions {
        /// 開始丟棄舊 helper 在下一次 `started` 之前送來的訊息。
        public var beginSwitch: () -> Void
        public var resetTicker: () -> Void
        public var restartHelper: ([String]) -> Void
        /// 新來源的標籤；nil = 沒有，改用 `style.json` 的 `labelText`。
        public var applyLabel: (String?) -> Void
        public init(beginSwitch: @escaping () -> Void, resetTicker: @escaping () -> Void,
                    restartHelper: @escaping ([String]) -> Void, applyLabel: @escaping (String?) -> Void) {
            self.beginSwitch = beginSwitch; self.resetTicker = resetTicker; self.restartHelper = restartHelper; self.applyLabel = applyLabel
        }
    }

    private let store: SourceRegistryStore
    public var storeURL: URL { store.url }
    private let available: Set<String>
    private let pollIntervalSeconds: () -> Int
    private let log: AppLog?
    private let actions: Actions
    public private(set) var current: String
    public private(set) var loaded: SourceRegistryStore.Loaded

    /// `environmentSource`：`NEWSTICKER_SOURCE` 的值。有值時優先使用（即使不在清單內），且**不寫** `selected`。
    public init(store: SourceRegistryStore, available: Set<String>, environmentSource: String?,
                pollIntervalSeconds: @escaping () -> Int, log: AppLog?, actions: Actions) {
        self.store = store; self.available = available; self.pollIntervalSeconds = pollIntervalSeconds; self.log = log; self.actions = actions
        let l = store.load()
        loaded = l
        current = environmentSource ?? l.registry.effectiveSelection(available: available)
        if let e = l.writeError { log?.write("sources: cannot write \(store.url.path): \(e)") }
        if let n = l.notice { log?.write("sources: \(n)") }
        for w in l.warnings { log?.write("sources: \(w)") }
        log?.write("sources: current=\(current) available=\(available.sorted().joined(separator: ",")) file=\(store.url.path)")
    }

    /// 啟動時要套用的標籤覆寫。
    public var initialLabel: String? { loaded.registry.entry(id: current)?.label }

    /// 選單即將開啟時呼叫：重讀檔案，手動編輯不需重啟。
    public func menuItems() -> [SourceMenuItem] {
        loaded = store.load()
        return SourceMenuModel.items(registry: loaded.registry, available: available, current: current, notice: loaded.notice)
    }

    /// 切換到 `id`。已是目前來源、清單裡沒有、或 helper 沒有該連接器時不做事並回傳 false。
    /// 寫檔失敗只記日誌：本次執行仍然切換成功。
    @discardableResult
    public func select(_ id: String) -> Bool {
        guard id != current, available.contains(id), let entry = loaded.registry.entry(id: id) else { return false }
        if !store.select(id) { log?.write("sources: could not persist selection \(id) (switched for this run only)") }
        current = id
        log?.write("sources: switching to \(id)")
        actions.beginSwitch()
        actions.resetTicker()
        actions.restartHelper(FeedClientConfig.helperArguments(pollIntervalSeconds: pollIntervalSeconds(), source: id))
        actions.applyLabel(entry.label)
        return true
    }
}
