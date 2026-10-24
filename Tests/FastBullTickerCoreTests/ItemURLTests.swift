import Testing
import Foundation
@testable import FastBullTickerCore

/// `url` 欄位規則（design 決定 1），與 protocol/schema/item.schema.json 逐條對應。
@Suite struct ItemURLTests {
    func itemWith(_ urlJSON: String?) -> String {
        let extra = urlJSON.map { #","url":\#($0)"# } ?? ""
        return #"{"v":1,"type":"items","items":[{"source":"fastbull","id":"1","published_at_ms":1,"text":"x"\#(extra)}]}"#
    }
    func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }
    func accepts(_ url: String) -> Bool { if case .success = decode(itemWith(jsonString(url))) { return true } else { return false } }

    @Test func missingUrlIsAcceptedAndNil() {
        guard case .success(.items(let items)) = decode(itemWith(nil)) else { Issue.record("rejected"); return }
        #expect(items[0].url == nil)
    }

    @Test func validUrlIsDecoded() {
        guard case .success(.items(let items)) = decode(itemWith(#""https://www.example.com/tw/fastshort/1""#)) else { Issue.record("rejected"); return }
        #expect(items[0].url == "https://www.example.com/tw/fastshort/1")
        #expect(accepts("http://a.example/x"))
        #expect(accepts("http://[::1]:8080/x"))
        #expect(accepts("https://a"))
    }

    @Test func nullIsRejectedAsSchema() {
        #expect(reason(decode(itemWith("null"))) == .schema)
    }

    @Test func nonStringIsRejected() {
        #expect(reason(decode(itemWith("123"))) == .schema)
        #expect(reason(decode(itemWith("true"))) == .schema)
        #expect(reason(decode(itemWith("[]"))) == .schema)
    }

    @Test func schemeRules() {
        #expect(!accepts("javascript:alert(1)"))
        #expect(!accepts("ftp://a.example/x"))
        #expect(!accepts("file:///etc/passwd"))
        #expect(!accepts("HTTPS://a.example/x"), "scheme 只接受小寫")
        #expect(!accepts("Http://a.example/x"))
        #expect(!accepts("/tw/fastshort/1"))
        #expect(!accepts("//a.example/x"))
        #expect(!accepts("a.example/x"))
    }

    @Test func hostFirstCharacterRules() {
        #expect(!accepts("https:///x"))
        #expect(!accepts("https://"))
        #expect(!accepts("https://-a.example/"))
        #expect(!accepts("https://.a.example/"))
        #expect(!accepts("https://@a.example/"))
    }

    @Test func emptyAndWhitespaceAndControlCharacters() {
        #expect(!accepts(""))
        #expect(!accepts("https://a b"))
        #expect(!accepts(" https://a.example/"))
        #expect(!accepts("https://a.example/ "))
        #expect(!accepts("https://a.example/\t"))
        #expect(!accepts("https://a.example/\n"), "結尾換行（Python $ 的分歧點）")
        #expect(!accepts("https://a.example/\r\n"))
        #expect(!accepts("https://a.example/\u{7F}"), "DEL 不是可見 ASCII")
        #expect(!accepts("https://a.example/\u{0}"))
    }

    @Test func nonASCIIIsRejected() {
        #expect(!accepts("https://a.example/中"))
        #expect(!accepts("https://a.example/\u{00A0}"))
        #expect(!accepts("https://ａ.example/"))
    }

    @Test func lengthBoundaryIs2048Bytes() {
        let pre = "https://example.com/"
        #expect(ProtocolRules.maxURLBytes == 2048)
        #expect(accepts(pre + String(repeating: "a", count: 2048 - pre.utf8.count)))
        #expect(!accepts(pre + String(repeating: "a", count: 2049 - pre.utf8.count)))
    }

    @Test func isValidURLMatchesDecoder() {
        let cases = ["https://a", "http://[::1]/x", "ftp://a", "", "https://a b", "https://a/\n", "https://a/中", "HTTP://a", "https:///"]
        for c in cases { #expect(ProtocolRules.isValidURL(c) == accepts(c), "\(c.debugDescription)") }
    }

    @Test func unknownExtraFieldIsStillRejected() {
        let s = #"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":1,"text":"x","urls":"y"}]}"#
        #expect(reason(decode(s)) == .schema)
    }

    @Test func mixedItemsKeepPerItemUrl() {
        let s = #"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":1,"text":"x"},{"source":"a","id":"2","published_at_ms":2,"text":"y","url":"https://a.example/2"}]}"#
        guard case .success(.items(let items)) = decode(s) else { Issue.record("rejected"); return }
        #expect(items.map(\.url) == [nil, "https://a.example/2"])
    }

    @Test func badUrlRejectsWholeMessage() {
        let s = #"{"v":1,"type":"items","items":[{"source":"a","id":"1","published_at_ms":1,"text":"x","url":"https://a.example/1"},{"source":"a","id":"2","published_at_ms":2,"text":"y","url":"javascript:x"}]}"#
        #expect(reason(decode(s)) == .schema)
    }

    @Test func memberwiseInitDefaultsUrlToNil() {
        #expect(Item(source: "a", id: "1", publishedAtMs: 1, text: "x").url == nil)
        #expect(Item(source: "a", id: "1", publishedAtMs: 1, text: "x", url: "https://a.example/").url == "https://a.example/")
    }
}
