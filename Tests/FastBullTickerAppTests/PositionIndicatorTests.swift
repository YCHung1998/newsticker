import Testing
import Foundation
@testable import FastBullTickerApp
import FastBullTickerCore

@Suite struct PositionIndicatorTests {
    private func pos(_ index: Int, _ total: Int) -> ReadingPosition {
        ReadingPosition(item: PlacedItem(source: "s", id: "1", style: .replay, timeString: "00:00:00", text: "t",
                                         truncated: false, tapeX: 0, width: 100), index: index, total: total)
    }

    @Test func formatsParenSlash() {
        #expect(PositionIndicator.text(for: pos(3, 10)) == "(3/10)")
        #expect(PositionIndicator.text(for: pos(2, 3)) == "(2/3)")
        #expect(PositionIndicator.text(for: pos(2, 4)) == "(2/4)")
    }

    @Test func boundariesAndTwoDigits() {
        #expect(PositionIndicator.text(for: pos(10, 10)) == "(10/10)")
        #expect(PositionIndicator.text(for: pos(1, 1)) == "(1/1)")
        #expect(PositionIndicator.text(for: pos(100, 1234)) == "(100/1234)", "無前導零、無千分位、無空白")
    }

    @Test func nilMeansEmptyNotZeroZero() {
        #expect(PositionIndicator.text(for: nil) == "")
    }

    @Test func invalidNumbersAreNotShown() {
        #expect(PositionIndicator.text(for: pos(0, 0)) == "")
        #expect(PositionIndicator.text(for: pos(1, 0)) == "")
    }

    @Test func usesAsciiDigitsRegardlessOfLocale() {
        let s = PositionIndicator.text(for: pos(7, 10))
        #expect(s.unicodeScalars.allSatisfy { $0.isASCII })
    }
}
