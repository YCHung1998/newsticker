import Foundation

// ticker-style-settings 1.1：樣式模型與驗證。只依賴 Foundation（不依賴 AppKit），全部為純函式。
//
// 命名注意：Core 另有 `FastBullTickerCore.TickerStyle`（`.live`／`.replay` 的列舉，標示訊息樣式類型）。
// 本檔的 `TickerStyle` 是 App 層的外觀設定結構（規格指定名稱）；在 App 目標內本檔宣告優先於匯入，
// 需要 Core 列舉時請寫 `FastBullTickerCore.TickerStyle`。

// MARK: 色彩

/// 不透明 sRGB 色彩，分量 0–1（由 8 位元值換算，故可精確往返 `#RRGGBB`）。
public struct RGBColor: Equatable, Sendable, Codable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public init(r8: UInt8, g8: UInt8, b8: UInt8) { self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255) }

    /// 只接受 `#` 加恰 6 個十六進位字元（大小寫皆可）；不接受 3 位縮寫、8 位（alpha）、色名、`rgb()`、不含 `#`。
    public init?(hex: String) {
        let u = Array(hex.utf8)
        guard u.count == 7, u[0] == 0x23 else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: return nil
            }
        }
        var v: [UInt8] = []
        for i in stride(from: 1, to: 7, by: 2) {
            guard let hi = nibble(u[i]), let lo = nibble(u[i + 1]) else { return nil }
            v.append(hi << 4 | lo)
        }
        self.init(r8: v[0], g8: v[1], b8: v[2])
    }

    public var bytes: (r: UInt8, g: UInt8, b: UInt8) {
        func q(_ x: Double) -> UInt8 { UInt8(min(max((x * 255).rounded(), 0), 255)) }
        return (q(r), q(g), q(b))
    }

    /// 正規化輸出：大寫 `#RRGGBB`。
    public var hex: String {
        let v = bytes
        return String(format: "#%02X%02X%02X", Int(v.r), Int(v.g), Int(v.b))
    }

    /// WCAG 相對亮度：`0.2126R + 0.7152G + 0.0722B`，分量先線性化。
    public var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = RGBColor(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "非法色碼：\(s)"))
        }
        self = c
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

/// WCAG 對比度 `(L1 + 0.05) / (L2 + 0.05)`，`L1` 為較亮者。
public enum ContrastRatio {
    /// 一般文字 AA；低於此值只警告、不阻擋【假設】。
    public static let threshold = 4.5
    public static func ratio(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: 範圍

/// 各欄位的合法範圍（【假設】，見 design.md 決定 1）。選單檔位與滑桿共用，避免兩處各寫一份。
public enum StyleRanges {
    public static let cornerRadius: ClosedRange<Double> = 0...21     // 面板高 42 的一半
    public static let fontSize: ClosedRange<Double> = 10...26
    public static let scrollSpeed: ClosedRange<Double> = 20...300
    public static let replayCount: ClosedRange<Int> = 3...30
    public static let labelTextLength: ClosedRange<Int> = 1...16
    /// settings-gear：左右切換後停留秒數【假設】。下限 0.5：設定面板不提供「關閉停留」（Core 的 0 仍合法，檔案中的 0 被夾制為 0.5）。
    public static let seekHoldSeconds: ClosedRange<Double> = 0.5...10
    /// settings-gear：輪詢間隔檔位（秒）【假設】。5 秒未實測，不提供。
    public static let pollIntervalSteps: [Int] = [10, 30, 60]
    public static let supportedVersion = 1
    public static let maxFileBytes = 64 * 1024
}

// MARK: 樣式

/// 單一集中的外觀與行為設定。預設值與 app-shell 原型逐項一致（`TickerStyleTests` 斷言）。
public struct TickerStyle: Equatable, Sendable, Codable {
    public var version: Int = StyleRanges.supportedVersion
    public var cornerRadius: Double
    public var fontSize: Double
    public var scrollSpeed: Double
    public var replayCount: Int
    public var showTime: Bool
    public var showLabel: Bool
    public var labelText: String
    public var labelBackground: RGBColor
    public var labelColor: RGBColor
    public var tapeBackground: RGBColor
    public var liveBackground: RGBColor
    public var liveText: RGBColor
    public var replayBackground: RGBColor
    public var replayText: RGBColor
    /// 左右切換後停留秒數（settings-gear）；經 Core `reconfigure` 生效。
    public var seekHoldSeconds: Double
    /// helper 輪詢間隔秒數（settings-gear），只能是 `StyleRanges.pollIntervalSteps` 之一；變更時重啟 helper。
    public var pollIntervalSeconds: Int

    /// JSON 鍵（順序即檔案欄位表；README 表格與測試比對這份清單）。
    public static let keys = ["version", "cornerRadius", "fontSize", "scrollSpeed", "replayCount", "showTime", "showLabel", "labelText",
                              "labelBackground", "labelColor", "tapeBackground", "liveBackground", "liveText", "replayBackground", "replayText",
                              "seekHoldSeconds", "pollIntervalSeconds"]

    /// 與原型一致的預設值。色碼為原型 RGB 浮點值的 8 位元量化（誤差 ≤ 1/255）：
    /// 空隙 (0.09, 0.09, 0.10) → `#17171A`、標籤紅 (0.85, 0.10, 0.13) → `#D91A21`。
    public static let `default` = TickerStyle(
        cornerRadius: 0, fontSize: 16, scrollSpeed: 90, replayCount: 10, showTime: true, showLabel: true,
        labelText: "即時財經快訊",
        labelBackground: RGBColor(hex: "#D91A21")!, labelColor: RGBColor(hex: "#FFFFFF")!,
        tapeBackground: RGBColor(hex: "#17171A")!,
        liveBackground: RGBColor(hex: "#FFFFFF")!, liveText: RGBColor(hex: "#000000")!,
        replayBackground: RGBColor(hex: "#000000")!, replayText: RGBColor(hex: "#FFFFFF")!,
        seekHoldSeconds: 1, pollIntervalSeconds: 10)

    /// 夾制到最近的輪詢檔位；平手取較大者（較少請求）。
    public static func nearestPollStep(_ v: Double) -> Int {
        var best = StyleRanges.pollIntervalSteps[0]
        for step in StyleRanges.pollIntervalSteps.dropFirst() where abs(Double(step) - v) <= abs(Double(best) - v) { best = step }
        return best
    }

    /// 每個欄位都在合法範圍內（`StyleParser` 的輸出永遠為真）。
    public var isValid: Bool {
        version == StyleRanges.supportedVersion
            && StyleRanges.cornerRadius.contains(cornerRadius) && StyleRanges.fontSize.contains(fontSize)
            && StyleRanges.scrollSpeed.contains(scrollSpeed) && StyleRanges.replayCount.contains(replayCount)
            && StyleRanges.labelTextLength.contains(labelText.count)
            && StyleRanges.seekHoldSeconds.contains(seekHoldSeconds) && StyleRanges.pollIntervalSteps.contains(pollIntervalSeconds)
            && labelText == labelText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把每個欄位夾進合法範圍（選單／程式修改後保證仍合法）；`labelText` 修剪空白、空則取預設、超長截斷。
    public func clamped() -> TickerStyle {
        var s = self
        func c(_ x: Double, _ r: ClosedRange<Double>) -> Double { min(max(x, r.lowerBound), r.upperBound) }
        s.version = StyleRanges.supportedVersion
        s.cornerRadius = c(cornerRadius, StyleRanges.cornerRadius)
        s.fontSize = c(fontSize, StyleRanges.fontSize)
        s.scrollSpeed = c(scrollSpeed, StyleRanges.scrollSpeed)
        s.replayCount = min(max(replayCount, StyleRanges.replayCount.lowerBound), StyleRanges.replayCount.upperBound)
        s.seekHoldSeconds = c(seekHoldSeconds, StyleRanges.seekHoldSeconds)
        s.pollIntervalSeconds = TickerStyle.nearestPollStep(Double(pollIntervalSeconds))
        let t = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        s.labelText = t.isEmpty ? TickerStyle.default.labelText : String(t.prefix(StyleRanges.labelTextLength.upperBound))
        return s
    }

    /// 正規化輸出：UTF-8 JSON、鍵排序、縮排、色碼大寫、結尾換行。
    public func normalizedJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var d = (try? enc.encode(self)) ?? Data("{}".utf8)
        d.append(0x0A)
        return d
    }
}

/// 即時配色預設（選單用；【假設】色碼需使用者看實物決定）。三組對比度皆 ≥ 4.5。
public struct LiveColorPreset: Equatable, Sendable {
    public let name: String
    public let background: RGBColor
    public let text: RGBColor
    public static let all: [LiveColorPreset] = [
        LiveColorPreset(name: "白底黑字", background: RGBColor(hex: "#FFFFFF")!, text: RGBColor(hex: "#000000")!),
        LiveColorPreset(name: "黃底黑字", background: RGBColor(hex: "#FFE45C")!, text: RGBColor(hex: "#000000")!),
        LiveColorPreset(name: "綠底白字", background: RGBColor(hex: "#1E7B3C")!, text: RGBColor(hex: "#FFFFFF")!),
    ]
}

// MARK: 解析與驗證

/// 整份檔案無法解讀（呼叫端保留舊值）。
public enum StyleLoadError: Error, Equatable, Sendable, CustomStringConvertible {
    case tooLarge(bytes: Int)
    case notUTF8
    case notJSON(String)
    case notObject
    case unsupportedVersion(String)

    public var description: String {
        switch self {
        case .tooLarge(let n): return "檔案過大（\(n) 位元組，上限 \(StyleRanges.maxFileBytes)）"
        case .notUTF8: return "不是 UTF-8"
        case .notJSON(let why): return "不是合法 JSON（\(why)）"
        case .notObject: return "頂層不是 JSON 物件"
        case .unsupportedVersion(let v): return "version 必須是整數 \(StyleRanges.supportedVersion)（讀到 \(v)）"
        }
    }
}

public struct StyleWarning: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable { case clamped, invalidType, invalidColor, invalidLabel, labelTruncated, unknownKey, lowContrast }
    public let kind: Kind
    public let key: String
    public let message: String
    public var description: String { "\(key): \(message)" }
}

public struct StyleParseResult: Equatable, Sendable {
    public let style: TickerStyle
    public let warnings: [StyleWarning]
    /// 檔案中出現的未知鍵（寫回前備份的判斷依據）。
    public var unknownKeys: [String] { warnings.filter { $0.kind == .unknownKey }.map(\.key) }
}

/// 最小 JSON 值（用 `JSONDecoder` 解碼，因此布林與數字不會互相誤判）。
private enum JSONValue: Decodable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    var typeName: String {
        switch self { case .null: "null"; case .bool: "布林"; case .number: "數字"; case .string: "字串"; case .array: "陣列"; case .object: "物件" }
    }
    var brief: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return String(b)
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .string(let s): return "\"\(s)\""
        case .array, .object: return typeName
        }
    }
}

public enum StyleParser {
    /// 純函式：只由 `data` 決定結果，不依賴先前狀態。
    /// - 整份失敗（`.failure`）：過大、非 UTF-8、非 JSON、頂層非物件、`version` 不是整數 1。
    /// - 欄位層級：越界夾制＋警告；型別錯誤與非法色碼取欄位預設值＋警告；未知鍵忽略＋警告；缺鍵取預設值（不警告）。
    /// - 對比度低於 4.5 只警告，照常套用。
    public static func parse(_ data: Data) -> Result<StyleParseResult, StyleLoadError> {
        guard data.count <= StyleRanges.maxFileBytes else { return .failure(.tooLarge(bytes: data.count)) }
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }      // 容忍 UTF-8 BOM
        guard String(data: bytes, encoding: .utf8) != nil else { return .failure(.notUTF8) }
        let root: JSONValue
        do { root = try JSONDecoder().decode(JSONValue.self, from: bytes) }
        catch { return .failure(.notJSON(String(describing: (error as? DecodingError).map(shortReason) ?? "解析失敗"))) }
        guard case .object(let obj) = root else { return .failure(.notObject) }

        if let v = obj["version"] {
            guard case .number(let n) = v, n == Double(StyleRanges.supportedVersion) else { return .failure(.unsupportedVersion(v.brief)) }
        }

        var s = TickerStyle.default
        var w: [StyleWarning] = []
        func warn(_ k: StyleWarning.Kind, _ key: String, _ msg: String) { w.append(StyleWarning(kind: k, key: key, message: msg)) }

        func double(_ key: String, _ range: ClosedRange<Double>, _ def: Double) -> Double {
            guard let v = obj[key] else { return def }
            guard case .number(let n) = v else { warn(.invalidType, key, "應為數字（讀到\(v.typeName)），改用預設值 \(def)"); return def }
            let c = min(max(n, range.lowerBound), range.upperBound)
            if c != n { warn(.clamped, key, "\(v.brief) 超出範圍 \(range.lowerBound)–\(range.upperBound)，夾制為 \(c)") }
            return c
        }
        func bool(_ key: String, _ def: Bool) -> Bool {
            guard let v = obj[key] else { return def }
            guard case .bool(let b) = v else { warn(.invalidType, key, "應為布林（讀到\(v.typeName) \(v.brief)），改用預設值 \(def)"); return def }
            return b
        }
        func color(_ key: String, _ def: RGBColor) -> RGBColor {
            guard let v = obj[key] else { return def }
            guard case .string(let str) = v else { warn(.invalidType, key, "應為 #RRGGBB 字串（讀到\(v.typeName)），改用預設值 \(def.hex)"); return def }
            guard let c = RGBColor(hex: str) else { warn(.invalidColor, key, "非法色碼 \(str)，改用預設值 \(def.hex)"); return def }
            return c
        }

        s.cornerRadius = double("cornerRadius", StyleRanges.cornerRadius, TickerStyle.default.cornerRadius)
        s.fontSize = double("fontSize", StyleRanges.fontSize, TickerStyle.default.fontSize)
        s.scrollSpeed = double("scrollSpeed", StyleRanges.scrollSpeed, TickerStyle.default.scrollSpeed)

        if let v = obj["replayCount"] {
            if case .number(let n) = v, n == n.rounded() {
                let lo = Double(StyleRanges.replayCount.lowerBound), hi = Double(StyleRanges.replayCount.upperBound)
                let c = min(max(n, lo), hi)
                if c != n { warn(.clamped, "replayCount", "\(v.brief) 超出範圍 \(Int(lo))–\(Int(hi))，夾制為 \(Int(c))") }
                s.replayCount = Int(c)
            } else {
                warn(.invalidType, "replayCount", "應為整數（讀到\(v.typeName) \(v.brief)），改用預設值 \(TickerStyle.default.replayCount)")
            }
        }
        s.seekHoldSeconds = double("seekHoldSeconds", StyleRanges.seekHoldSeconds, TickerStyle.default.seekHoldSeconds)
        if let v = obj["pollIntervalSeconds"] {
            if case .number(let n) = v, n == n.rounded() {
                let step = TickerStyle.nearestPollStep(n)
                if Double(step) != n { warn(.clamped, "pollIntervalSeconds", "\(v.brief) 不是檔位 \(StyleRanges.pollIntervalSteps.map(String.init).joined(separator: "／"))，夾制為最近的 \(step)") }
                s.pollIntervalSeconds = step
            } else {
                warn(.invalidType, "pollIntervalSeconds", "應為整數檔位（讀到\(v.typeName) \(v.brief)），改用預設值 \(TickerStyle.default.pollIntervalSeconds)")
            }
        }
        s.showTime = bool("showTime", TickerStyle.default.showTime)
        s.showLabel = bool("showLabel", TickerStyle.default.showLabel)

        if let v = obj["labelText"] {
            if case .string(let raw) = v {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty {
                    warn(.invalidLabel, "labelText", "修剪空白後為空，改用預設值")
                } else if t.count > StyleRanges.labelTextLength.upperBound {
                    s.labelText = String(t.prefix(StyleRanges.labelTextLength.upperBound))
                    warn(.labelTruncated, "labelText", "超過 \(StyleRanges.labelTextLength.upperBound) 個字元，截為前 \(StyleRanges.labelTextLength.upperBound) 個")
                } else {
                    s.labelText = t
                }
            } else {
                warn(.invalidType, "labelText", "應為字串（讀到\(v.typeName)），改用預設值")
            }
        }

        let d = TickerStyle.default
        s.labelBackground = color("labelBackground", d.labelBackground)
        s.labelColor = color("labelColor", d.labelColor)
        s.tapeBackground = color("tapeBackground", d.tapeBackground)
        s.liveBackground = color("liveBackground", d.liveBackground)
        s.liveText = color("liveText", d.liveText)
        s.replayBackground = color("replayBackground", d.replayBackground)
        s.replayText = color("replayText", d.replayText)

        for k in obj.keys.sorted() where !TickerStyle.keys.contains(k) { warn(.unknownKey, k, "未知的鍵，已忽略") }

        for (name, fg, bg) in [("live", s.liveText, s.liveBackground), ("replay", s.replayText, s.replayBackground), ("label", s.labelColor, s.labelBackground)] {
            let ratio = ContrastRatio.ratio(fg, bg)
            if ratio < ContrastRatio.threshold {
                warn(.lowContrast, name, String(format: "文字與背景對比度 %.2f:1 低於 %.1f:1，仍照常套用", ratio, ContrastRatio.threshold))
            }
        }
        return .success(StyleParseResult(style: s, warnings: w))
    }

    private static func shortReason(_ e: DecodingError) -> String {
        switch e {
        case .dataCorrupted(let c): return c.debugDescription
        default: return "結構錯誤"
        }
    }
}
