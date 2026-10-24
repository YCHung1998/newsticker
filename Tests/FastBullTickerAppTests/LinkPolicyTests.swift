import Testing
import Foundation
@testable import FastBullTickerApp

@Suite struct LinkPolicyTests {
    @Test func acceptsPlainHttpAndHttps() {
        let u = LinkPolicy.openableURL(from: "https://www.fastbull.com/tw/fastshort/4334051_1_2")
        #expect(u?.url.absoluteString == "https://www.fastbull.com/tw/fastshort/4334051_1_2")
        #expect(LinkPolicy.openableURL(from: "http://example.test/a?b=1#c")?.url.scheme == "http")
        #expect(LinkPolicy.openableURL(from: "HTTPS://example.test/")?.url.host?.lowercased() == "example.test")
        #expect(LinkPolicy.openableURL(from: "https://[::1]/x") != nil)
        #expect(LinkPolicy.openableURL(from: "https://example.test:8443/x") != nil)
    }

    @Test func rejectsNonHttpSchemes() {
        for bad in ["javascript:alert(1)", "file:///etc/hosts", "ftp://example.test/a", "mailto:a@b.c",
                    "data:text/html,<b>x</b>", "tel:+886", "x-apple.systempreferences:", "about:blank", "//example.test/a", "example.test/a"] {
            #expect(LinkPolicy.openableURL(from: bad) == nil, "\(bad)")
        }
    }

    @Test func rejectsUserinfoAndMissingHost() {
        for bad in ["https://user:pw@example.test/", "https://user@example.test/", "https://:pw@example.test/",
                    "https:///path", "https://", "http://:80/x"] {
            #expect(LinkPolicy.openableURL(from: bad) == nil, "\(bad)")
        }
        #expect(LinkPolicy.openableURL(from: "https://example.test/a@b") != nil, "路徑中的 @ 不是 userinfo")
    }

    @Test func rejectsOverlongAndAcceptsExactLimit() {
        let prefix = "https://example.test/"
        let atLimit = prefix + String(repeating: "a", count: 2048 - prefix.utf8.count)
        #expect(atLimit.utf8.count == 2048 && LinkPolicy.openableURL(from: atLimit) != nil)
        #expect(LinkPolicy.openableURL(from: atLimit + "a") == nil)
    }

    @Test func rejectsEmptyWhitespaceAndControlCharacters() {
        for bad in ["", " ", "https://example.test/a b", "https://example.test/\n", "https://example.test/\t",
                    " https://example.test/", "https://example.test/\u{0}x", "https://exa mple.test/", "https://example.test/中文"] {
            #expect(LinkPolicy.openableURL(from: bad) == nil, "\(bad.debugDescription)")
        }
    }
}

@MainActor
@Suite struct LinkOpeningTests {
    @Test func opensExactlyOnceWithTheValidatedURL() {
        let opener = RecordingURLOpener()
        let r = LinkOpening.open("https://example.test/a", using: opener)
        #expect(r == .opened && opener.opened.map(\.absoluteString) == ["https://example.test/a"])
    }

    @Test func blockedURLsNeverReachTheOpener() {
        let opener = RecordingURLOpener()
        let inputs: [String?] = ["javascript:alert(1)", "file:///etc/hosts", nil, "https://u:p@example.test/", "https:///x", "ftp://x/y"]
        for i in inputs { _ = LinkOpening.open(i, using: opener) }
        #expect(opener.opened.isEmpty)
        #expect(LinkOpening.open("javascript:alert(1)", using: opener) == .blockedByPolicy)
        #expect(LinkOpening.open(nil, using: opener) == .noURL)
    }

    @Test func mixedClicksOnlyRecordHttpOrHttps() {
        let opener = RecordingURLOpener()
        let urls: [String?] = ["https://example.test/1", "javascript:x", "http://example.test/2", nil, "file:///tmp/x", "https://example.test/3"]
        for u in urls { _ = LinkOpening.open(u, using: opener) }
        #expect(opener.opened.count == 3)
        #expect(opener.opened.allSatisfy { $0.scheme == "http" || $0.scheme == "https" })
    }

    @Test func openerFailureIsReportedNotRetried() {
        let opener = RecordingURLOpener()
        opener.result = false
        #expect(LinkOpening.open("https://example.test/a", using: opener) == .openerFailed)
        #expect(opener.opened.count == 1, "不重試")
    }
}
