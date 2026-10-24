import Testing
import Foundation
@testable import FastBullTickerCore

private func b(_ s: String) -> [UInt8] { Array(s.utf8) }
private func lines(_ evs: [LineEvent]) -> [String] {
    evs.map { if case .line(let l) = $0 { return String(decoding: l, as: UTF8.self) } else { return "<\($0)>" } }
}

@Suite struct LineBufferTests {
    @Test func multipleLinesInOneChunk() {
        var lb = LineBuffer()
        #expect(lines(lb.feed(b("a\nb\nc\n"))) == ["a", "b", "c"])
    }

    @Test func halfLineAcrossChunks() {
        var lb = LineBuffer()
        #expect(lb.feed(b(#"{"v":1,"#)).isEmpty)
        #expect(lines(lb.feed(b(#""type":"status"}"# + "\n"))) == [#"{"v":1,"type":"status"}"#])
    }

    @Test func utf8CharacterSplitAcrossChunks() {
        let full = b("中文\n")   // 「中」= E4 B8 AD
        var whole = LineBuffer()
        let expected = whole.feed(full)
        var split = LineBuffer()
        var got = split.feed(Array(full[0..<2]))          // 切在字元中間
        got += split.feed(Array(full[2...]))
        #expect(got == expected)
        #expect(got == [.line(b("中文"))])
    }

    @Test func byteByByteEqualsWhole() {
        let data = b("alpha\n\n中文\nlast\npartial")
        var whole = LineBuffer()
        let expected = whole.feed(data)
        var one = LineBuffer()
        var got: [LineEvent] = []
        for byte in data { got += one.feed([byte]) }
        #expect(got == expected)
        #expect(lines(got) == ["alpha", "", "中文", "last"])
    }

    @Test func exactlyAtLimitIsEmitted() {
        var lb = LineBuffer(maxLineBytes: 8)
        let evs = lb.feed(b("12345678\n"))
        #expect(evs == [.line(b("12345678"))])
    }

    @Test func limitPlusOneIsDroppedThenRecovers() {
        var lb = LineBuffer(maxLineBytes: 8)
        let evs = lb.feed(b("123456789\nok\n"))
        #expect(evs == [.oversize(discardedBytes: 9), .line(b("ok"))])
    }

    @Test func oversizeAcrossManyChunksBoundedBufferAndSingleEvent() {
        var lb = LineBuffer(maxLineBytes: 8)
        var all: [LineEvent] = []
        var maxBuffered = 0
        for _ in 0..<1000 {                       // 1000 個 chunk × 10 bytes，遠超上限
            all += lb.feed(b("0123456789"))
            maxBuffered = max(maxBuffered, lb.bufferedCount)
        }
        #expect(lb.isDiscarding)
        #expect(all.isEmpty, "0x0A 未到達前不應輸出任何事件")
        #expect(maxBuffered <= 8, "緩衝不得隨超長行成長：\(maxBuffered)")
        all += lb.feed(b("\nnext\n"))
        #expect(all == [.oversize(discardedBytes: 10_000), .line(b("next"))])
        #expect(!lb.isDiscarding)
    }

    @Test func oversizeChunkedEqualsWhole() {
        let data = b("123456789012345\nok\n12345678\n")
        var whole = LineBuffer(maxLineBytes: 8)
        let expected = whole.feed(data)
        var one = LineBuffer(maxLineBytes: 8)
        var got: [LineEvent] = []
        for byte in data { got += one.feed([byte]) }
        #expect(got == expected)
        #expect(expected == [.oversize(discardedBytes: 15), .line(b("ok")), .line(b("12345678"))])
    }

    @Test func emptyLinesAreReported() {
        var lb = LineBuffer()
        #expect(lines(lb.feed(b("a\n\nb\n"))) == ["a", "", "b"])
    }

    @Test func trailingHalfLineAtEOFIsNotEmitted() {
        var lb = LineBuffer()
        #expect(lines(lb.feed(b("a\nb"))) == ["a"])
        #expect(lb.bufferedCount == 1)
        #expect(lb.finish() == 1)          // 殘留 1 byte 被丟棄，不輸出
        #expect(lb.bufferedCount == 0)
    }

    @Test func defaultLimitIsContractLimit() {
        #expect(LineBuffer().maxLineBytes == 1_048_576)
    }

    @Test func goodGarbageGoodIntegration() {
        let good1 = #"{"v":1,"type":"status","source":"a","state":"ok","message":"A"}"#
        let good2 = #"{"v":1,"type":"status","source":"a","state":"ok","message":"B"}"#
        var lb = LineBuffer()
        var results: [String] = []
        for ev in lb.feed(b(good1 + "\n" + "garbage ✗ not json\n" + good2 + "\n")) {
            switch ev {
            case .oversize: results.append("oversize")
            case .line(let l):
                switch decodeLine(l) {
                case .success(.status(let s)): results.append("ok:" + s.message)
                case .success: results.append("other")
                case .failure(let e): results.append("err:" + e.reason.rawValue)
                }
            }
        }
        #expect(results == ["ok:A", "err:not_json", "ok:B"])
    }

    @Test func realLimitBoundaryWithGeneratedLines() {
        var lb = LineBuffer()
        let atLimit = [UInt8](repeating: 0x61, count: ProtocolRules.maxLineBytes)
        let evs = lb.feed(atLimit + [0x0A] + atLimit + [0x62, 0x0A] + b("z\n"))
        guard evs.count == 3 else { Issue.record("事件數 \(evs.count) != 3"); return }
        #expect(evs[0] == .line(atLimit))
        #expect(evs[1] == .oversize(discardedBytes: ProtocolRules.maxLineBytes + 1))
        #expect(evs[2] == .line(b("z")))
    }
}
