import Foundation

/// 協定規則常數：message-contract 的嚴格性集中於此（2026-10-24 已決定，以 `protocol/` 為準）。
public enum ProtocolRules {
    /// 單行上限（位元組，不含 0x0A）；恰為上限合法。
    public static let maxLineBytes = 1_048_576
    public static let supportedVersion = 1
    /// 額外欄位一律拒絕（Codable 預設會忽略，必須手寫檢查）。
    public static let rejectExtraFields = true
    /// 空 `items` 非法。
    public static let allowEmptyItems = false
    /// `text` 不得為空字串。
    public static let allowEmptyText = false
    /// 順序違規拒絕（`order`）。
    public static let enforceOrder = true
    /// `url` 上限（位元組）。僅可見 ASCII，所以位元組數等於字元數。
    public static let maxURLBytes = 2048

    /// `url` 規則，與 `protocol/schema/item.schema.json` 完全一致（逐位元組，不依賴 Foundation 的字串／URL 解析）：
    /// 長度 1...2048、每個位元組 0x21...0x7E、小寫 `http://` 或 `https://` 開頭、其後第一個位元組為英數或 `[`。
    public static func isValidURL(_ s: String) -> Bool {
        let b = Array(s.utf8)
        guard !b.isEmpty, b.count <= maxURLBytes, b.allSatisfy({ (0x21...0x7E).contains($0) }) else { return false }
        let http = Array("http://".utf8), https = Array("https://".utf8)
        let prefix: Int
        if b.starts(with: https) { prefix = https.count } else if b.starts(with: http) { prefix = http.count } else { return false }
        guard prefix < b.count else { return false }
        let c = b[prefix]
        let alnum = (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
        return alnum || c == 0x5B
    }
}

/// 單則訊息。v1 不含「重要」旗標。
public struct Item: Equatable, Sendable, Codable {
    public var source: String
    public var id: String
    public var publishedAtMs: Int64
    public var text: String
    /// 選填原文連結；`nil` = 無連結（協定中缺少該鍵）。`null` 在解碼時被拒絕。
    public var url: String?

    public init(source: String, id: String, publishedAtMs: Int64, text: String, url: String? = nil) {
        self.source = source; self.id = id; self.publishedAtMs = publishedAtMs; self.text = text; self.url = url
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case source, id, text, url
        case publishedAtMs = "published_at_ms"
    }

    public init(from decoder: Decoder) throws {
        try StrictKeys.check(decoder, expected: CodingKeys.allCases)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        id = try c.decode(String.self, forKey: .id)
        publishedAtMs = try c.decode(Int64.self, forKey: .publishedAtMs)
        text = try c.decode(String.self, forKey: .text)
        // 區分「缺少」與 null：decodeIfPresent 會把 null 當成 nil，所以先看鍵是否存在。
        if c.contains(.url) {
            if try c.decodeNil(forKey: .url) {
                throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "url 不得為 null（缺少才代表無連結）")
            }
            url = try c.decode(String.self, forKey: .url)
        } else {
            url = nil
        }
        func bad(_ k: CodingKeys, _ why: String) -> DecodingError {
            .dataCorruptedError(forKey: k, in: c, debugDescription: why)
        }
        if source.isEmpty { throw bad(.source, "source 不得為空") }
        if id.isEmpty { throw bad(.id, "id 不得為空") }
        if publishedAtMs < 0 { throw bad(.publishedAtMs, "published_at_ms 不得為負") }
        if text.isEmpty && !ProtocolRules.allowEmptyText { throw bad(.text, "text 不得為空") }
        if let u = url, !ProtocolRules.isValidURL(u) { throw bad(.url, "url 不合法（需可見 ASCII、小寫 http(s)、<= 2048 位元組）") }
    }
}

public struct Status: Equatable, Sendable, Codable {
    public enum State: String, Equatable, Sendable, Codable { case ok, error }
    public var source: String
    public var state: State
    public var message: String

    public init(source: String, state: State, message: String) {
        self.source = source; self.state = state; self.message = message
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case v, type, source, state, message }

    public init(from decoder: Decoder) throws {
        try StrictKeys.check(decoder, expected: CodingKeys.allCases)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try StrictKeys.checkEnvelope(c, type: "status")
        source = try c.decode(String.self, forKey: .source)
        state = try c.decode(State.self, forKey: .state)
        message = try c.decode(String.self, forKey: .message)
        if source.isEmpty { throw DecodingError.dataCorruptedError(forKey: .source, in: c, debugDescription: "source 不得為空") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ProtocolRules.supportedVersion, forKey: .v)
        try c.encode("status", forKey: .type)
        try c.encode(source, forKey: .source)
        try c.encode(state, forKey: .state)
        try c.encode(message, forKey: .message)
    }
}

/// `snapshot`／`items` 共用的承載（內部使用）。
struct ItemsPayload: Decodable {
    var items: [Item]
    enum CodingKeys: String, CodingKey, CaseIterable { case v, type, items }
    init(from decoder: Decoder) throws {
        try StrictKeys.check(decoder, expected: CodingKeys.allCases)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        try StrictKeys.checkEnvelope(c, type: t)
        items = try c.decode([Item].self, forKey: .items)  // 任一 item 非法 → 整則丟出
        if items.isEmpty && !ProtocolRules.allowEmptyItems {
            throw DecodingError.dataCorruptedError(forKey: .items, in: c, debugDescription: "items 不得為空")
        }
    }
}

enum StrictKeys {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// `v` 必須是整數 1；`type` 必須符合預期。
    static func checkEnvelope<K: CodingKey>(_ c: KeyedDecodingContainer<K>, type expected: String) throws {
        guard let vKey = K(stringValue: "v"), let tKey = K(stringValue: "type") else { return }
        let v = try c.decode(Int.self, forKey: vKey)
        let t = try c.decode(String.self, forKey: tKey)
        if v != ProtocolRules.supportedVersion || t != expected {
            throw DecodingError.dataCorruptedError(forKey: vKey, in: c, debugDescription: "v/type 不符")
        }
    }

    /// 拒絕未定義的額外欄位（受 `ProtocolRules.rejectExtraFields` 控制）。
    static func check<K: CodingKey>(_ decoder: Decoder, expected: [K]) throws {
        guard ProtocolRules.rejectExtraFields else { return }
        let c = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(expected.map(\.stringValue))
        let extra = c.allKeys.map(\.stringValue).filter { !allowed.contains($0) }
        if !extra.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "未定義欄位: \(extra.sorted())"))
        }
    }
}

public enum Message: Equatable, Sendable {
    case snapshot([Item])   // 新到舊
    case items([Item])      // 舊到新
    case status(Status)
}

/// 與 manifest `reasons` 一一對應。
public enum DecodeErrorReason: String, CaseIterable, Sendable {
    case notJSON = "not_json"
    case schema
    case version
    case oversize
    case order
}

public struct DecodeError: Error, Equatable, Sendable {
    public var reason: DecodeErrorReason
    public var detail: String
    public init(_ reason: DecodeErrorReason, _ detail: String = "") { self.reason = reason; self.detail = detail }
}
