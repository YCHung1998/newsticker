import Foundation

/// 文字寬度量測（注入）。單位與 tape 座標相同。Core 不自行使用任何字型／文字量測 API。
public typealias TextMeasurer = (String) -> Double

/// 24 小時制 `HH:mm:ss`，以注入的時區表示。不使用 DateFormatter／Locale，故不受系統語系與 12/24 小時設定影響。
public struct TimeFormatter: Sendable {
    public var timeZone: TimeZone
    public init(timeZone: TimeZone) { self.timeZone = timeZone }

    public func string(forMs ms: Int64) -> String {
        let seconds = Int64((Double(ms) / 1000).rounded(.down))
        let offset = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(seconds)))
        let local = seconds + Int64(offset)
        let secOfDay = Int(((local % 86_400) + 86_400) % 86_400)
        let h = secOfDay / 3600, m = (secOfDay % 3600) / 60, s = secOfDay % 60
        return pad2(h) + ":" + pad2(m) + ":" + pad2(s)
    }

    private func pad2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
}

/// 量測時需要知道「開頭多少個 UTF-16 單位為粗體」的量測函式（時間＋標題連續位於顯示字串開頭）。
/// 只有含標題的訊息會用到；其餘仍走 `TextMeasurer`，行為與舊版相同。
public typealias BoldAwareMeasurer = (_ text: String, _ boldPrefixUTF16: Int) -> Double

/// 單則訊息的版面結果（與渲染方案無關）。
public struct ItemLayout: Equatable, Sendable {
    public var timeString: String
    /// 可能被截斷（以「…」結尾）的文字。
    public var text: String
    /// 標題（顯示在時間與本文之間，粗體）；沒有標題為空字串。
    public var title: String = ""
    /// 來源標示為重要（`Item.important == true`）。
    public var important: Bool = false
    /// `measurer(displayString)`。
    public var width: Double
    public var truncated: Bool
    /// 有 `url` 且 `linkSlotWidth` > 0：`width` 已含最右側的連結欄位，命中區（訊息本地座標）為 `[width − linkSlotWidth, width)`。
    public var hasLinkSlot: Bool = false
    /// 供量測與繪製的顯示字串：時間字串、一個空白、文字【假設】。`showTime` 為 false 時 `timeString` 為空，顯示字串只有文字。
    public var displayString: String {
        let head = [timeString, title].filter { !$0.isEmpty }.joined(separator: " ")
        return head.isEmpty ? text : head + " " + text
    }
    /// 開頭粗體區段（時間＋標題，含兩者之間的空白）的 UTF-16 長度；無時間無標題為 0。
    public var boldPrefixUTF16: Int { [timeString, title].filter { !$0.isEmpty }.joined(separator: " ").utf16.count }
}

public let ellipsis = "…"

/// 以量測寬度截斷：顯示字串寬度超過 `maxWidth`（有連結欄位時為 `maxWidth − linkSlotWidth`）時，取「時間 + 空白 + 最長可行前綴 + …」使寬度 ≤ 預算。
/// 截斷單位為 Character（grapheme cluster）。假設 measurer 對前綴長度單調不減（二分搜尋）。
/// 連「…」都放不下時輸出「時間 + 空白 + …」（寬度可能仍超過 `maxWidth`）。
/// `showTime`（預設 true）：false 時不含時間字串與分隔空白（`timeString` 為空字串），量測與截斷以純文字為準。
/// `linkSlotWidth`（預設 0）：只有 `item.url != nil` 且 `linkSlotWidth > 0` 時才保留欄位（`width` 加欄位、`hasLinkSlot` 為 true）；否則與舊行為完全相同。
public func layoutItem(_ item: Item, timeZone: TimeZone, maxWidth: Double, linkSlotWidth: Double = 0, showTime: Bool = true, measurer: TextMeasurer, boldMeasurer: BoldAwareMeasurer? = nil) -> ItemLayout {
    let time = showTime ? TimeFormatter(timeZone: timeZone).string(forMs: item.publishedAtMs) : ""
    let title = item.title ?? ""
    let head = [time, title].filter { !$0.isEmpty }.joined(separator: " ")
    let prefix = head.isEmpty ? "" : head + " "
    let boldN = head.utf16.count
    // 含標題且有粗體量測器時，連標題一起以粗體量測；否則（含所有無標題的訊息）走原本的量測。
    func measure(_ s: String) -> Double { (title.isEmpty || boldMeasurer == nil) ? measurer(s) : boldMeasurer!(s, boldN) }
    let slot = (item.url != nil && linkSlotWidth > 0) ? linkSlotWidth : 0
    let hasSlot = slot > 0
    let budget = maxWidth - slot
    let fullWidth = measure(prefix + item.text)
    if fullWidth <= budget {
        return ItemLayout(timeString: time, text: item.text, title: title, important: item.important == true, width: fullWidth + slot, truncated: false, hasLinkSlot: hasSlot)
    }
    let chars = Array(item.text)
    func candidate(_ k: Int) -> String { String(chars[0..<k]) + ellipsis }
    // 找最大的 k（0...chars.count-1）使 measurer(prefix + candidate(k)) <= budget；k = -1 表示連 k=0 都放不下。
    var lo = -1, hi = chars.count - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if measure(prefix + candidate(mid)) <= budget { lo = mid } else { hi = mid - 1 }
    }
    let text = candidate(max(lo, 0))
    return ItemLayout(timeString: time, text: text, title: title, important: item.important == true, width: measure(prefix + text) + slot, truncated: true, hasLinkSlot: hasSlot)
}
