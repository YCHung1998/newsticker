import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

/// 命中測試與控制列版面（tasks 6.1；nav-layout-tweaks 改為控制列在標籤右側）。純函式，不開視窗。
/// 幾何（預設）：面板 620×42、標籤 0..<150、控制列 150..<250（`<` 150..<174、指示 174..<226、`>` 226..<250）、帶子可視區 250..<620。
@Suite struct HitTestingTests {
    private let geo = HitGeometry(panelSize: CGSize(width: 620, height: 42), labelWidth: 150,
                                  strip: ControlStripLayout(), linkSlotWidth: 26, hitSlop: 4)

    /// 訊息寬 200，視覺左緣（帶子座標）100 → 面板 x = 350...550，連結欄位 524..<550（含 slop 520..<554）。
    private let linked = HitItem(seq: 7, visualLeft: 100, width: 200, hasLinkSlot: true)
    private let plain = HitItem(seq: 8, visualLeft: 300, width: 100, hasLinkSlot: false)

    private func hit(_ x: Double, _ y: Double = 21, items: [HitItem]? = nil, in g: HitGeometry? = nil) -> HitTarget {
        HitTesting.target(at: CGPoint(x: x, y: y), in: g ?? geo, items: items ?? [linked, plain])
    }

    @Test func buttonsAreInTheControlStripRightOfTheLabel() {
        #expect(hit(150) == .previousButton && hit(173.9) == .previousButton)
        #expect(hit(174) == .drag && hit(200) == .drag && hit(225.9) == .drag, "位置指示不是按鈕")
        #expect(hit(226) == .nextButton && hit(249.9) == .nextButton)
        #expect(hit(149.9) == .drag, "標籤")
        #expect(hit(520) == .link(seq: 7) && hit(600) == .drag, "原本控制列所在的面板右端現在是帶子，不再是按鈕")
    }

    @Test func buttonsFollowLabelWidthWhenLabelHidden() {
        var g = geo; g.labelWidth = 0                      // showLabel = false：控制列貼面板左緣
        #expect(hit(0, in: g) == .previousButton && hit(23.9, in: g) == .previousButton)
        #expect(hit(24, in: g) == .drag && hit(75.9, in: g) == .drag)
        #expect(hit(76, in: g) == .nextButton && hit(99.9, in: g) == .nextButton)
        // 帶子座標 0 → 面板 x = 100：連結欄位右緣 = 100 + 100 + 200 = 400 → 欄位 374..<400
        #expect(hit(380, in: g) == .link(seq: 7) && hit(300, in: g) == .drag)
    }

    @Test func linkZoneIncludingHitSlop() {
        #expect(hit(520) == .link(seq: 7), "左側外擴 4pt")
        #expect(hit(524) == .link(seq: 7) && hit(549) == .link(seq: 7))
        #expect(hit(553.9) == .link(seq: 7), "右側外擴 4pt")
        #expect(hit(519.9) == .drag && hit(554) == .drag)
        #expect(hit(530, 0) == .link(seq: 7) && hit(530, 41.9) == .link(seq: 7), "整條帶高")
    }

    @Test func itemWithoutLinkSlotIsDrag() {
        #expect(hit(390) == .drag, "plain 訊息最右側（其 slot 並不存在）")
        let only = [plain]
        #expect(hit(649 - 100, items: only) == .drag)
    }

    // 連結欄位區間 = [右緣 − 26 − 4, 右緣 + 4)，右緣 = 250（控制列右緣）+ visualLeft + width。
    @Test func buttonBeatsLinkBeneathIt() {
        let underNext = HitItem(seq: 9, visualLeft: -100, width: 100, hasLinkSlot: true)    // 右緣 250：區間 220..<254 蓋住 `>`（226..<250）
        #expect(hit(240, items: [underNext]) == .nextButton)
        #expect(hit(200, items: [underNext]) == .drag, "控制列內的位置指示：不是連結")
        #expect(hit(252, items: [underNext]) == .link(seq: 9), "控制列右緣之外（可視帶子內）仍有效")
        let straddlePrev = HitItem(seq: 11, visualLeft: -70, width: 0, hasLinkSlot: true)   // 右緣 180：區間 150..<184 蓋住 `<`（150..<174）
        #expect(hit(160, items: [straddlePrev]) == .previousButton)
        #expect(hit(176, items: [straddlePrev]) == .drag, "位置指示不是連結")
    }

    @Test func linkHiddenByLabelOrStripIsNotALink() {
        let inLabel = HitItem(seq: 2, visualLeft: -260, width: 150, hasLinkSlot: true)      // 右緣 140：區間 110..<144 全在標籤內
        #expect(hit(120, items: [inLabel]) == .drag && hit(143, items: [inLabel]) == .drag)
        let straddleStripEnd = HitItem(seq: 4, visualLeft: -80, width: 100, hasLinkSlot: true) // 右緣 270：區間 240..<274 跨過控制列右緣 250
        #expect(hit(249, items: [straddleStripEnd]) == .nextButton, "控制列範圍內無效（按鈕優先）")
        #expect(hit(250, items: [straddleStripEnd]) == .link(seq: 4), "控制列右緣起（可視帶子內）有效")
        let inStrip = HitItem(seq: 5, visualLeft: -140, width: 100, hasLinkSlot: true)      // 右緣 210：區間 180..<214 全在控制列內
        #expect(hit(200, items: [inStrip]) == .drag && hit(213, items: [inStrip]) == .drag)
    }

    @Test func everythingElseIsDrag() {
        #expect(hit(10) == .drag, "標籤")
        #expect(hit(300) == .drag, "訊息文字")
        #expect(hit(500, items: []) == .drag, "空白處")
        #expect(hit(-1) == .drag && hit(620) == .drag && hit(300, -0.1) == .drag && hit(300, 42) == .drag, "面板外")
    }

    @Test func zeroLinkSlotWidthDisablesAllLinks() {
        var g = geo; g.linkSlotWidth = 0
        #expect(HitTesting.target(at: CGPoint(x: 540, y: 21), in: g, items: [linked]) == .drag)
    }

    @Test func firstMatchingLinkWinsWhenSlopsOverlap() {
        let a = HitItem(seq: 1, visualLeft: 0, width: 100, hasLinkSlot: true)       // 右緣 350：區間 320..<354
        let b = HitItem(seq: 2, visualLeft: 30, width: 100, hasLinkSlot: true)      // 右緣 380：區間 350..<384
        #expect(hit(340, items: [a, b]) == .link(seq: 1))
        #expect(hit(370, items: [a, b]) == .link(seq: 2))
        #expect(hit(352, items: [a, b]) == .link(seq: 1) && hit(352, items: [b, a]) == .link(seq: 2), "重疊處以陣列順序為準")
    }
}

@Suite struct ControlStripLayoutTests {
    @Test func defaultWidthIsHundred() {
        let l = ControlStripLayout()
        #expect(l.buttonWidth == 24 && l.indicatorWidth == 52 && l.controlStripWidth == 100)
    }

    @Test func tapeViewportWidthFormula() {
        #expect(ControlStripLayout().tapeViewportWidth(panelWidth: 620, labelWidth: 150) == 370)
        #expect(ControlStripLayout().tapeViewportWidth(panelWidth: 620, labelWidth: 0) == 520, "標籤隱藏")
        #expect(ControlStripLayout().tapeViewportWidth(panelWidth: 100, labelWidth: 150) == 0, "不為負")
    }

    @Test func rangesTileTheStripRightOfTheLabel() {
        let l = ControlStripLayout()
        #expect(l.previousButtonRange(leftInset: 150) == 150..<174)
        #expect(l.indicatorRange(leftInset: 150) == 174..<226)
        #expect(l.nextButtonRange(leftInset: 150) == 226..<250)
        #expect(l.stripRange(leftInset: 150) == 150..<250)
        #expect(l.tapeLeft(leftInset: 150) == 250, "帶子座標 0（readingInset 參考線與 seek 對齊位置）＝控制列右緣")
    }

    @Test func rangesWithoutLabelStartAtPanelLeft() {
        let l = ControlStripLayout()
        #expect(l.stripRange(leftInset: 0) == 0..<100 && l.previousButtonRange(leftInset: 0) == 0..<24)
        #expect(l.nextButtonRange(leftInset: 0) == 76..<100 && l.tapeLeft(leftInset: 0) == 100)
    }

    /// 預留齒輪槽：只要把 leftInset 加上槽寬 G，控制列內部相對版面與可視寬度公式都不用改。
    @Test func gearSlotCanBeInsertedByShiftingTheSingleOffset() {
        let l = ControlStripLayout()
        let g = 40.0
        for inset in [0.0, 150.0] {
            func rel(_ r: Range<Double>, _ i: Double) -> [Double] { [r.lowerBound - i, r.upperBound - i] }
            #expect(rel(l.previousButtonRange(leftInset: inset + g), inset + g) == rel(l.previousButtonRange(leftInset: inset), inset))
            #expect(rel(l.indicatorRange(leftInset: inset + g), inset + g) == rel(l.indicatorRange(leftInset: inset), inset))
            #expect(rel(l.nextButtonRange(leftInset: inset + g), inset + g) == rel(l.nextButtonRange(leftInset: inset), inset))
            #expect(l.tapeViewportWidth(panelWidth: 620, labelWidth: inset + g) == l.tapeViewportWidth(panelWidth: 620, labelWidth: inset) - g)
        }
    }
}
