import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp

/// 結束 ✕ 的命中與路由（change quit-controls）。純邏輯，不開視窗。
/// 幾何：面板 620×42、標籤 150、控制列 150..<250、帶子 250..<620、✕ 區 592..<620。
@MainActor
@Suite struct QuitHitTests {
    private func geo(_ quit: Double = 28) -> HitGeometry {
        HitGeometry(panelSize: CGSize(width: 620, height: 42), labelWidth: 150, strip: ControlStripLayout(),
                    linkSlotWidth: 26, hitSlop: 4, quitSlotWidth: quit)
    }
    /// 迴紋針欄位右緣 600 → 命中區 570..<604，與 ✕ 區（592..）重疊 592..<604。
    private let overlapping = HitItem(seq: 5, visualLeft: 250, width: 100, hasLinkSlot: true)

    private func hit(_ x: Double, _ y: Double = 21, items: [HitItem] = [], g: HitGeometry? = nil) -> HitTarget {
        HitTesting.target(at: CGPoint(x: x, y: y), in: g ?? geo(), items: items)
    }

    @Test func quitZoneIsTheRightmostSlotHalfOpen() {
        #expect(hit(592) == .quit && hit(619.9) == .quit)
        #expect(hit(591.9) == .drag)
        #expect(hit(620) == .drag && hit(-1) == .drag, "面板外")
        #expect(hit(600, 0) == .quit && hit(600, 41.9) == .quit, "整條帶高")
        #expect(hit(600, 42) == .drag)
    }

    @Test func zeroWidthSlotMeansNoQuitTargetSoExistingGeometriesAreUnchanged() {
        #expect(hit(610, g: geo(0)) == .drag)
        let legacy = HitGeometry(panelSize: CGSize(width: 620, height: 42), labelWidth: 150, strip: ControlStripLayout(), linkSlotWidth: 26, hitSlop: 4)
        #expect(legacy.quitSlotWidth == 0)
        #expect(HitTesting.target(at: CGPoint(x: 610, y: 21), in: legacy, items: []) == .drag)
    }

    @Test func quitWinsOverAnOverlappingLinkButOnlyInTheSlot() {
        #expect(hit(595, items: [overlapping]) == .quit, "重疊處：結束優先")
        #expect(hit(580, items: [overlapping]) == .link(seq: 5), "還沒進到 ✕ 區的迴紋針照常可點")
        #expect(hit(571, items: [overlapping]) == .link(seq: 5))
    }

    @Test func gearAndControlStripAreUnaffected() {
        #expect(hit(155) == .previousButton && hit(230) == .nextButton)
        var withGear = geo(); withGear.gearSlotWidth = 28
        #expect(hit(10, g: withGear) == .gear)
    }

    // MARK: 路由

    private func router(enabled: Bool = true) -> (NavigationInputRouter, () -> Int) {
        let r = NavigationInputRouter(geometry: geo())
        r.isEnabled = enabled
        var quits = 0
        r.onQuit = { quits += 1 }
        return (r, { quits })
    }

    @Test func mouseUpOnTheSameTargetQuitsOnce() {
        let (r, quits) = router()
        var dragged = 0
        let t = r.mouseDown(at: CGPoint(x: 600, y: 20), button: .left, performDrag: { dragged += 1 })
        #expect(t == .quit && dragged == 0, "按下 ✕ 不是拖曳")
        #expect(quits() == 0, "mouse-down 不觸發")
        #expect(r.mouseUp(at: CGPoint(x: 605, y: 10), button: .left))
        #expect(quits() == 1)
    }

    @Test func pressThenReleaseElsewhereCancels() {
        let (r, quits) = router()
        r.mouseDown(at: CGPoint(x: 600, y: 20), button: .left, performDrag: {})
        #expect(r.mouseUp(at: CGPoint(x: 400, y: 20), button: .left) == false)
        #expect(quits() == 0)
    }

    @Test func pressElsewhereThenReleaseOnQuitDoesNotQuit() {
        let (r, quits) = router()
        r.mouseDown(at: CGPoint(x: 400, y: 20), button: .left, performDrag: {})
        #expect(r.mouseUp(at: CGPoint(x: 600, y: 20), button: .left) == false)
        #expect(quits() == 0)
    }

    @Test func rightAndOtherButtonsNeverQuit() {
        let (r, quits) = router()
        #expect(r.mouseDown(at: CGPoint(x: 600, y: 20), button: .right, performDrag: {}) == nil)
        #expect(r.mouseUp(at: CGPoint(x: 600, y: 20), button: .right) == false)
        #expect(r.mouseDown(at: CGPoint(x: 600, y: 20), button: .other, performDrag: {}) == nil)
        #expect(quits() == 0)
    }

    @Test func clickThroughDisablesQuit() {
        let (r, quits) = router(enabled: false)
        #expect(r.mouseDown(at: CGPoint(x: 600, y: 20), button: .left, performDrag: {}) == nil)
        #expect(r.mouseUp(at: CGPoint(x: 600, y: 20), button: .left) == false)
        #expect(quits() == 0)
    }

    @Test func otherTargetsStillWork() {
        let (r, _) = router()
        var prev = 0
        r.onPrevious = { prev += 1 }
        r.mouseDown(at: CGPoint(x: 155, y: 20), button: .left, performDrag: {})
        #expect(r.mouseUp(at: CGPoint(x: 155, y: 20), button: .left) && prev == 1)
    }
}
