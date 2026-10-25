import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

// settings-gear task 1：齒輪槽版面與面板寬度推導。純函式＋離屏圖層（不開視窗）。執行：swift test --filter GearLayout
// 預設版面：面板 648×42；齒輪槽 0..<28、標籤 28..<178、控制列 178..<278（`<` 178..<202、指示 202..<254、`>` 254..<278）、帶子可視區 278..<648。
@MainActor
@Suite struct GearLayoutTests {
    @Test func defaultPanelWidthIsDerivedNotHardCoded() {
        let c = ShellConfig.provisional
        #expect(c.gearSlotWidth == 28)
        #expect(c.panelSize.width == 648 && c.panelSize.height == 42)
        let derived = ShellConfig.panelWidth(gearSlotWidth: c.gearSlotWidth, labelWidth: Double(c.labelWidth), strip: c.strip,
                                             tapeViewport: ShellConfig.designTapeViewport)
        #expect(derived == 28 + 150 + 100 + 370 && Double(c.panelSize.width) == derived)
    }

    @Test func panelWidthFollowsGearSlotWidthAndKeepsViewport370() {
        let strip = ControlStripLayout()
        for g in [0.0, 24, 28, 40] {
            let w = ShellConfig.panelWidth(gearSlotWidth: g, labelWidth: 150, strip: strip, tapeViewport: 370)
            #expect(w == g + 150 + 100 + 370)
            var c = ShellConfig.provisional
            c.gearSlotWidth = g
            c.panelSize = CGSize(width: w, height: 42)
            #expect(c.tapeViewport(showLabel: true) == 370, "槽寬 \(g)：可視寬度仍為 370")
            #expect(c.tapeViewport(showLabel: false) == 520)
        }
    }

    @Test func viewportAndSchedulerConfigIncludeTheGearSlot() {
        let c = ShellConfig.provisional
        #expect(c.tapeViewport(showLabel: true) == 370 && c.tapeViewport(showLabel: false) == 520)
        #expect(c.tapeViewportWidth == 370)
        #expect(c.schedulerConfig().viewportWidth == 370)
        var s = TickerStyle.default; s.showLabel = false
        #expect(c.schedulerConfig(style: s).viewportWidth == 520)
    }

    @Test func hitGeometryCarriesGearSlotAndLabelSeparately() {
        let g = ShellConfig.provisional.makeHitGeometry(showLabel: true)
        #expect(g.gearSlotWidth == 28 && g.labelWidth == 150 && g.panelSize.width == 648)
        let n = ShellConfig.provisional.makeHitGeometry(showLabel: false)
        #expect(n.gearSlotWidth == 28 && n.labelWidth == 0, "標籤隱藏時齒輪槽仍在")
    }

    @Test func layersAreLaidOutWithLabelShiftedByTheGearSlot() {
        let v = TickerView(config: .provisional)
        let l = v.layoutSnapshot
        #expect(Double(l.gearSlotFrame.minX) == 0 && Double(l.gearSlotFrame.maxX) == 28)
        #expect(Double(l.labelFrame.minX) == 28 && Double(l.labelFrame.maxX) == 178)
        #expect(Double(l.previousFrame.minX) == 178 && Double(l.indicatorFrame.minX) == 202 && Double(l.nextFrame.minX) == 254 && Double(l.nextFrame.maxX) == 278)
        #expect(Double(l.clipFrame.minX) == 278 && Double(l.clipFrame.maxX) == 648 && Double(l.clipFrame.width) == 370)
        #expect(Double(l.gearFrame.minX) == 0 && Double(l.gearFrame.width) == 28)
    }

    @Test func hiddenLabelKeepsGearAtLeftAndStripRightNextToIt() {
        var s = TickerStyle.default; s.showLabel = false
        let v = TickerView(config: .provisional, style: s)
        let l = v.layoutSnapshot
        #expect(l.labelHidden)
        #expect(Double(l.gearSlotFrame.minX) == 0 && Double(l.gearSlotFrame.maxX) == 28)
        #expect(Double(l.previousFrame.minX) == 28 && Double(l.nextFrame.maxX) == 128)
        #expect(Double(l.clipFrame.minX) == 128 && Double(l.clipFrame.maxX) == 648 && Double(l.clipFrame.width) == 520)
    }

    @Test func togglingLabelMovesStripButNotGear() {
        let v = TickerView(config: .provisional)
        var s = TickerStyle.default; s.showLabel = false
        v.apply(style: s)
        #expect(Double(v.layoutSnapshot.previousFrame.minX) == 28 && Double(v.layoutSnapshot.gearSlotFrame.minX) == 0)
        #expect(v.router.geometry.gearSlotWidth == 28 && v.router.geometry.labelWidth == 0)
        v.apply(style: .default)
        #expect(Double(v.layoutSnapshot.previousFrame.minX) == 178 && v.router.geometry.labelWidth == 150)
    }

    @Test func controlStripLayoutIsOnlyTranslatedByTheGearSlot() {
        let l = ControlStripLayout()
        for inset in [0.0, 28, 178] {
            #expect(l.stripRange(leftInset: inset).lowerBound == inset)
            #expect(l.previousButtonRange(leftInset: inset) == inset..<(inset + 24))
            #expect(l.nextButtonRange(leftInset: inset).upperBound == inset + 100)
            #expect(l.tapeLeft(leftInset: inset) == inset + 100)
        }
    }
}
