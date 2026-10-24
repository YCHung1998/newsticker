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

/// 單則訊息的版面結果（與渲染方案無關）。
public struct ItemLayout: Equatable, Sendable {
    public var timeString: String
    /// 可能被截斷（以「…」結尾）的文字。
    public var text: String
    /// `measurer(displayString)`。
    public var width: Double
    public var truncated: Bool
    /// 有 `url` 且 `linkSlotWidth` > 0：`width` 已含最右側的連結欄位，命中區（訊息本地座標）為 `[width − linkSlotWidth, width)`。
    public var hasLinkSlot: Bool = false
    /// 供量測與繪製的顯示字串：時間字串、一個空白、文字【假設】。
    public var displayString: String { timeString + " " + text }
}

public let ellipsis = "…"

/// 以量測寬度截斷：顯示字串寬度超過 `maxWidth`（有連結欄位時為 `maxWidth − linkSlotWidth`）時，取「時間 + 空白 + 最長可行前綴 + …」使寬度 ≤ 預算。
/// 截斷單位為 Character（grapheme cluster）。假設 measurer 對前綴長度單調不減（二分搜尋）。
/// 連「…」都放不下時輸出「時間 + 空白 + …」（寬度可能仍超過 `maxWidth`）。
/// `linkSlotWidth`（預設 0）：只有 `item.url != nil` 且 `linkSlotWidth > 0` 時才保留欄位（`width` 加欄位、`hasLinkSlot` 為 true）；否則與舊行為完全相同。
public func layoutItem(_ item: Item, timeZone: TimeZone, maxWidth: Double, linkSlotWidth: Double = 0, measurer: TextMeasurer) -> ItemLayout {
    let time = TimeFormatter(timeZone: timeZone).string(forMs: item.publishedAtMs)
    let prefix = time + " "
    let slot = (item.url != nil && linkSlotWidth > 0) ? linkSlotWidth : 0
    let hasSlot = slot > 0
    let budget = maxWidth - slot
    let fullWidth = measurer(prefix + item.text)
    if fullWidth <= budget {
        return ItemLayout(timeString: time, text: item.text, width: fullWidth + slot, truncated: false, hasLinkSlot: hasSlot)
    }
    let chars = Array(item.text)
    func candidate(_ k: Int) -> String { String(chars[0..<k]) + ellipsis }
    // 找最大的 k（0...chars.count-1）使 measurer(prefix + candidate(k)) <= budget；k = -1 表示連 k=0 都放不下。
    var lo = -1, hi = chars.count - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if measurer(prefix + candidate(mid)) <= budget { lo = mid } else { hi = mid - 1 }
    }
    let text = candidate(max(lo, 0))
    return ItemLayout(timeString: time, text: text, width: measurer(prefix + text) + slot, truncated: true, hasLinkSlot: hasSlot)
}
