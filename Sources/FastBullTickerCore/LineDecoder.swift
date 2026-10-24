import Foundation

/// 單行解碼（輸入不含結尾 0x0A）。回傳錯誤值而不丟出，單行失敗不影響串流。
///
/// 判定順序（與 `protocol/README.md` 一致）：oversize → not_json → version → schema → order。
/// 整則拒絕：`items`／`snapshot` 任一 item 非法即整則 `schema`。
public func decodeLine(_ bytes: [UInt8]) -> Result<Message, DecodeError> {
    if bytes.count > ProtocolRules.maxLineBytes {
        return .failure(DecodeError(.oversize, "\(bytes.count) bytes"))
    }
    let data = Data(bytes)
    // 1. UTF-8（Foundation 的 JSON 解析對無效 UTF-8 的行為不一，先明確檢查）。
    guard String(data: data, encoding: .utf8) != nil else {
        return .failure(DecodeError(.notJSON, "invalid UTF-8"))
    }
    // 2. JSON 語法（空行、截斷、NaN 等都在此被擋下）。
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
        return .failure(DecodeError(.notJSON, "\(error)"))
    }
    guard let dict = object as? [String: Any] else {
        return .failure(DecodeError(.schema, "top-level is not an object"))
    }
    // 3. 版本：v 為整數且不等於 1 → version（不看其餘欄位）。
    if let v = dict["v"] as? NSNumber, isInteger(v), v.int64Value != Int64(ProtocolRules.supportedVersion) {
        return .failure(DecodeError(.version, "v=\(v)"))
    }
    // 4. schema（Codable 加手寫檢查）。
    guard let type = dict["type"] as? String else {
        return .failure(DecodeError(.schema, "missing or non-string type"))
    }
    let decoder = JSONDecoder()
    do {
        switch type {
        case "status":
            return .success(.status(try decoder.decode(Status.self, from: data)))
        case "snapshot":
            let items = try decoder.decode(ItemsPayload.self, from: data).items
            if ProtocolRules.enforceOrder, !isOrdered(items, descending: true) { return .failure(DecodeError(.order, "snapshot must be newest-first")) }
            return .success(.snapshot(items))
        case "items":
            let items = try decoder.decode(ItemsPayload.self, from: data).items
            if ProtocolRules.enforceOrder, !isOrdered(items, descending: false) { return .failure(DecodeError(.order, "items must be oldest-first")) }
            return .success(.items(items))
        default:
            return .failure(DecodeError(.schema, "unknown type \(type)"))
        }
    } catch {
        return .failure(DecodeError(.schema, "\(error)"))
    }
}

private func isInteger(_ n: NSNumber) -> Bool {
    if CFGetTypeID(n) == CFBooleanGetTypeID() { return false }
    return !CFNumberIsFloatType(n)
}

/// 相鄰相等視為合法（非嚴格單調）。
private func isOrdered(_ items: [Item], descending: Bool) -> Bool {
    zip(items, items.dropFirst()).allSatisfy { a, b in
        descending ? a.publishedAtMs >= b.publishedAtMs : a.publishedAtMs <= b.publishedAtMs
    }
}
