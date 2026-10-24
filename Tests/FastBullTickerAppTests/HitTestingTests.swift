import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

/// 命中測試與控制列版面（tasks 6.1）。純函式，不開視窗。
/// 幾何（預設）：面板 620×42、標籤 0..<150、控制列 520..<620（`<` 520..<544、指示 544..<596、`>` 596..<620）。
@Suite struct HitTestingTests {
    private let geo = HitGeometry(panelSize: CGSize(width: 620, height: 42), labelWidth: 150,
                                  strip: ControlStripLayout(), linkSlotWidth: 26, hitSlop: 4)

    /// 訊息寬 200，視覺左緣（帶子座標）100 → 面板 x = 250...450，連結欄位 424..<450（含 slop 420..<454）。
    private let linked = HitItem(seq: 7, visualLeft: 100, width: 200, hasLinkSlot: true)
    private let plain = HitItem(seq: 8, visualLeft: 300, width: 100, hasLinkSlot: false)

    private func hit(_ x: Double, _ y: Double = 21, items: [HitItem]? = nil) -> HitTarget {
        HitTesting.target(at: CGPoint(x: x, y: y), in: geo, items: items ?? [linked, plain])
    }

    @Test func buttonsAreInTheControlStrip() {
        #expect(hit(520) == .previousButton && hit(543.9) == .previousButton)
        #expect(hit(544) == .drag && hit(570) == .drag && hit(595.9) == .drag, "位置指示不是按鈕")
        #expect(hit(596) == .nextButton && hit(619.9) == .nextButton)
    }

    @Test func linkZoneIncludingHitSlop() {
        #expect(hit(420) == .link(seq: 7), "左側外擴 4pt")
        #expect(hit(424) == .link(seq: 7) && hit(449) == .link(seq: 7))
        #expect(hit(453.9) == .link(seq: 7), "右側外擴 4pt")
        #expect(hit(419.9) == .drag && hit(454) == .drag)
        #expect(hit(430, 0) == .link(seq: 7) && hit(430, 41.9) == .link(seq: 7), "整條帶高")
    }

    @Test func itemWithoutLinkSlotIsDrag() {
        #expect(hit(390) == .drag, "plain 訊息最右側（面板 x 390..<450 區間內其 slot 並不存在）")
        let only = [plain]
        #expect(hit(449, items: only) == .drag)
    }

    // 連結欄位區間 = [右緣 − 26 − 4, 右緣 + 4)，右緣 = 150（標籤）+ visualLeft + width。
    @Test func buttonBeatsLinkBeneathIt() {
        let underNext = HitItem(seq: 9, visualLeft: 270, width: 200, hasLinkSlot: true)     // 右緣 620：區間 590..<624 蓋住 `>`
        #expect(hit(600, items: [underNext]) == .nextButton)
        #expect(hit(570, items: [underNext]) == .drag, "控制列內的位置指示：不是連結")
        let straddlePrev = HitItem(seq: 11, visualLeft: 230, width: 160, hasLinkSlot: true) // 右緣 540：區間 510..<544 跨過 `<` 左緣 520
        #expect(hit(525, items: [straddlePrev]) == .previousButton)
        #expect(hit(515, items: [straddlePrev]) == .link(seq: 11), "控制列左緣之外仍有效")
    }

    @Test func linkHiddenByLabelOrStripIsNotALink() {
        let inLabel = HitItem(seq: 2, visualLeft: -160, width: 150, hasLinkSlot: true)      // 右緣 140：區間 110..<144 全在標籤內
        #expect(hit(120, items: [inLabel]) == .drag && hit(143, items: [inLabel]) == .drag)
        let straddleLabel = HitItem(seq: 4, visualLeft: -130, width: 150, hasLinkSlot: true) // 右緣 170：區間 140..<174 跨過標籤右緣 150
        #expect(hit(149, items: [straddleLabel]) == .drag, "標籤範圍內無效")
        #expect(hit(150, items: [straddleLabel]) == .link(seq: 4), "標籤右緣起（可見帶子內）有效")
        let inStrip = HitItem(seq: 5, visualLeft: 340, width: 100, hasLinkSlot: true)       // 右緣 590：區間 560..<594 全在控制列內
        #expect(hit(570, items: [inStrip]) == .drag && hit(593, items: [inStrip]) == .drag)
    }

    @Test func everythingElseIsDrag() {
        #expect(hit(10) == .drag, "標籤")
        #expect(hit(300) == .drag, "訊息文字")
        #expect(hit(500, items: []) == .drag, "空白處")
        #expect(hit(-1) == .drag && hit(620) == .drag && hit(300, -0.1) == .drag && hit(300, 42) == .drag, "面板外")
    }

    @Test func zeroLinkSlotWidthDisablesAllLinks() {
        var g = geo; g.linkSlotWidth = 0
        #expect(HitTesting.target(at: CGPoint(x: 440, y: 21), in: g, items: [linked]) == .drag)
    }

    @Test func firstMatchingLinkWinsWhenSlopsOverlap() {
        let a = HitItem(seq: 1, visualLeft: 0, width: 100, hasLinkSlot: true)       // 右緣 250：區間 220..<254
        let b = HitItem(seq: 2, visualLeft: 30, width: 100, hasLinkSlot: true)      // 右緣 280：區間 250..<284
        #expect(hit(240, items: [a, b]) == .link(seq: 1))
        #expect(hit(270, items: [a, b]) == .link(seq: 2))
        #expect(hit(252, items: [a, b]) == .link(seq: 1) && hit(252, items: [b, a]) == .link(seq: 2), "重疊處以陣列順序為準")
    }
}

@Suite struct ControlStripLayoutTests {
    @Test func defaultWidthIsHundred() {
        let l = ControlStripLayout()
        #expect(l.buttonWidth == 24 && l.indicatorWidth == 52 && l.controlStripWidth == 100)
    }

    @Test func tapeViewportWidthFormula() {
        #expect(ControlStripLayout().tapeViewportWidth(panelWidth: 620, labelWidth: 150) == 370)
        #expect(ControlStripLayout().tapeViewportWidth(panelWidth: 100, labelWidth: 150) == 0, "不為負")
    }

    @Test func rangesTileTheStripAtTheRightEnd() {
        let l = ControlStripLayout()
        #expect(l.previousButtonRange(panelWidth: 620) == 520..<544)
        #expect(l.indicatorRange(panelWidth: 620) == 544..<596)
        #expect(l.nextButtonRange(panelWidth: 620) == 596..<620)
        #expect(l.stripRange(panelWidth: 620) == 520..<620)
    }
}
