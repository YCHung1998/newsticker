import Testing
import Foundation
@testable import FastBullTickerCore

func line(_ s: String) -> [UInt8] { Array(s.utf8) }
func decode(_ s: String) -> Result<Message, DecodeError> { decodeLine(line(s)) }
func reason(_ r: Result<Message, DecodeError>) -> DecodeErrorReason? {
    if case .failure(let e) = r { return e.reason } else { return nil }
}

let itemJSON = #"{"source":"fastbull","id":"1","published_at_ms":1792832201957,"text":"hello"}"#

@Suite struct ProtocolDecodingTests {
    @Test func decodesSnapshotPreservingOrder() throws {
        let s = #"{"v":1,"type":"snapshot","items":[{"source":"a","id":"2","published_at_ms":30,"text":"x"},{"source":"a","id":"1","published_at_ms":20,"text":"y"}]}"#
        guard case .success(.snapshot(let items)) = decode(s) else { Issue.record("not snapshot"); return }
        #expect(items.map(\.id) == ["2", "1"])
        #expect(items[0] == Item(source: "a", id: "2", publishedAtMs: 30, text: "x"))
    }

    @Test func decodesItems() {
        guard case .success(.items(let items)) = decode(#"{"v":1,"type":"items","items":[\#(itemJSON)]}"#) else { Issue.record("not items"); return }
        #expect(items.count == 1 && items[0].publishedAtMs == 1792832201957)
    }

    @Test func decodesStatusError() {
        let r = decode(#"{"v":1,"type":"status","source":"fastbull","state":"error","message":"boom"}"#)
        #expect(r == .success(.status(Status(source: "fastbull", state: .error, message: "boom"))))
    }

    @Test func statusOkMayHaveEmptyMessage() {
        let r = decode(#"{"v":1,"type":"status","source":"fastbull","state":"ok","message":""}"#)
        #expect(r == .success(.status(Status(source: "fastbull", state: .ok, message: ""))))
    }

    @Test func notJSON() {
        #expect(reason(decode("not json at all")) == .notJSON)
        #expect(reason(decode("")) == .notJSON)
        #expect(reason(decode(#"{"v":1,"type":"status""#)) == .notJSON)
    }

    @Test func invalidUTF8IsNotJSON() {
        let bytes: [UInt8] = Array(#"{"v":1,"type":"status","source":"a","state":"ok","message":""#.utf8) + [0xFF, 0xFE] + Array(#""}"#.utf8)
        #expect(reason(decodeLine(bytes)) == .notJSON)
    }

    @Test func unsupportedVersionDoesNotLookAtRest() {
        // 其餘欄位根本不合法，仍應回報 version 而不是 schema。
        #expect(reason(decode(#"{"v":2,"type":"items","items":"garbage","zzz":1}"#)) == .version)
    }

    @Test func versionNonIntegerIsSchema() {
        #expect(reason(decode(#"{"v":"1","type":"items","items":[\#(itemJSON)]}"#)) == .schema)
        #expect(reason(decode(#"{"type":"items","items":[\#(itemJSON)]}"#)) == .schema)
    }

    @Test func mixedInvalidItemRejectsWholeMessage() {
        let bad = #"{"source":"fastbull","published_at_ms":1,"text":"no id"}"#
        let r = decode(#"{"v":1,"type":"items","items":[\#(itemJSON),\#(itemJSON.replacingOccurrences(of: "\"1\"", with: "\"2\"")),\#(bad)]}"#)
        #expect(reason(r) == .schema)
        if case .success = r { Issue.record("不得回傳部分合法 item") }
    }

    @Test func idAsNumberRejected() {
        let r = decode(#"{"v":1,"type":"items","items":[{"source":"a","id":1,"published_at_ms":1,"text":"x"}]}"#)
        #expect(reason(r) == .schema)
    }

    @Test func publishedAtWrongTypes() {
        for v in [#""1""#, "1.5", "-1", "true", "null"] {
            let r = decode(#"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":\#(v),"text":"x"}]}"#)
            #expect(reason(r) == .schema, "published_at_ms=\(v)")
        }
    }

    @Test func emptyItemsRejected() {
        #expect(reason(decode(#"{"v":1,"type":"items","items":[]}"#)) == .schema)
        #expect(reason(decode(#"{"v":1,"type":"snapshot","items":[]}"#)) == .schema)
    }

    @Test func emptyTextRejected() {
        #expect(reason(decode(#"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":1,"text":""}]}"#)) == .schema)
    }

    @Test func extraFieldsRejected() {
        #expect(reason(decode(#"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":1,"text":"x","important":true}]}"#)) == .schema)
        #expect(reason(decode(#"{"v":1,"type":"items","items":[\#(itemJSON)],"extra":1}"#)) == .schema)
        #expect(reason(decode(#"{"v":1,"type":"status","source":"a","state":"ok","message":"","extra":1}"#)) == .schema)
    }

    @Test func badStatusState() {
        #expect(reason(decode(#"{"v":1,"type":"status","source":"a","state":"warn","message":""}"#)) == .schema)
    }

    @Test func unknownAndMissingType() {
        #expect(reason(decode(#"{"v":1,"type":"hello"}"#)) == .schema)
        #expect(reason(decode(#"{"v":1}"#)) == .schema)
        #expect(reason(decode("[1,2]")) == .schema)
    }

    @Test func orderViolations() {
        let a = #"{"source":"a","id":"1","published_at_ms":10,"text":"x"}"#
        let b = #"{"source":"a","id":"2","published_at_ms":20,"text":"y"}"#
        #expect(reason(decode(#"{"v":1,"type":"items","items":[\#(b),\#(a)]}"#)) == .order)      // items 須舊到新
        #expect(reason(decode(#"{"v":1,"type":"snapshot","items":[\#(a),\#(b)]}"#)) == .order)   // snapshot 須新到舊
        #expect(reason(decode(#"{"v":1,"type":"items","items":[\#(a),\#(a)]}"#)) == nil)         // 相等合法
    }

    @Test func oversizeBeatsEverything() {
        let bytes = [UInt8](repeating: 0x61, count: ProtocolRules.maxLineBytes + 1)  // 不是 JSON，但先判 oversize
        #expect(reason(decodeLine(bytes)) == .oversize)
    }

    @Test func rulesConstants() {
        #expect(ProtocolRules.maxLineBytes == 1_048_576)
        #expect(ProtocolRules.supportedVersion == 1)
    }
}
