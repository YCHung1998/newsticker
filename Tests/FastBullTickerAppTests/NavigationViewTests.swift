import Testing
import Foundation
import AppKit
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

// task 7.1：滑鼠事件分派（NavigationInputRouter）與 TickerView 的 hover 追蹤。執行：swift test --filter NavigationView
// 不開視窗、不開瀏覽器：直接呼叫處理方法，動作用計數器替身。

@MainActor
private final class Probe {
    var previous = 0, next = 0, links: [Int] = [], drags = 0
    let router: NavigationInputRouter
    /// 面板 620×42、標籤 0..<150、控制列 150..<250（`<` 150..<174、指示 174..<226、`>` 226..<250）、帶子 250..<620；一則有連結的訊息：視覺左緣 100、寬 200 → 連結欄位 524..<550。
    static let geometry = ShellConfig.provisional.hitGeometry
    static let linked = HitItem(seq: 7, visualLeft: 100, width: 200, hasLinkSlot: true)
    init() {
        router = NavigationInputRouter(geometry: Probe.geometry)
        router.hitItems = { [Probe.linked] }
        router.onPrevious = { [unowned self] in previous += 1 }
        router.onNext = { [unowned self] in next += 1 }
        router.onLink = { [unowned self] in links.append($0) }
    }
    func down(_ x: Double, button: PointerButton = .left) { router.mouseDown(at: CGPoint(x: x, y: 21), button: button, performDrag: { self.drags += 1 }) }
    func up(_ x: Double, button: PointerButton = .left) { router.mouseUp(at: CGPoint(x: x, y: 21), button: button) }
    func click(_ x: Double) { down(x); up(x) }
}

@MainActor
@Suite struct NavigationViewTests {
    @Test func geometryComesFromShellConfig() {
        #expect(Probe.geometry.strip.controlStripWidth == 100 && Probe.geometry.labelWidth == 150)
        #expect(Probe.geometry.linkSlotWidth == 26 && Probe.geometry.hitSlop == 4)
    }

    @Test func buttonsFireOnMouseUpNotMouseDown() {
        let p = Probe()
        p.down(160)
        #expect(p.previous == 0 && p.drags == 0, "按下時不觸發、也不拖曳")
        p.up(160)
        #expect(p.previous == 1 && p.next == 0)
        p.click(240)
        #expect(p.next == 1)
    }

    @Test func linkFiresOnMouseUpWithItsSeq() {
        let p = Probe()
        p.down(540)
        #expect(p.links.isEmpty)
        p.up(540)
        #expect(p.links == [7] && p.drags == 0)
    }

    @Test func releasingOutsideThePressedTargetDoesNotFire() {
        let p = Probe()
        p.down(160); p.up(240)            // 在 < 按下、移到 > 放開
        p.down(160); p.up(300)            // 移到帶子放開
        p.down(540); p.up(300)            // 迴紋針按下、移開放開
        p.down(540); p.up(160)
        #expect(p.previous == 0 && p.next == 0 && p.links.isEmpty)
    }

    @Test func mouseUpWithoutMatchingMouseDownDoesNothing() {
        let p = Probe()
        p.up(160); p.up(540)
        #expect(p.previous == 0 && p.links.isEmpty)
    }

    @Test func rightAndOtherButtonsNeverTrigger() {
        let p = Probe()
        for b in [PointerButton.right, .other] {
            p.down(160, button: b); p.up(160, button: b)
            p.down(540, button: b); p.up(540, button: b)
            p.down(300, button: b); p.up(300, button: b)       // 右鍵／其他鍵也不拖曳
        }
        #expect(p.previous == 0 && p.next == 0 && p.links.isEmpty && p.drags == 0)
    }

    @Test func onlyDragTargetCallsPerformDrag() {
        let p = Probe()
        p.down(300)                       // 訊息文字
        #expect(p.drags == 1)
        p.up(300)
        p.down(60)                        // 標籤
        #expect(p.drags == 2)
        p.down(200)                       // 位置指示（不是按鈕）
        #expect(p.drags == 3)
        p.down(160); p.down(540)          // 按鈕、迴紋針：不拖曳
        #expect(p.drags == 3)
    }

    @Test func dragThenReleaseOverButtonDoesNotFire() {
        let p = Probe()
        p.down(300)                       // 拖曳開始
        p.up(160)
        #expect(p.previous == 0)
    }

    @Test func disabledRouterIgnoresEverything() {
        let p = Probe()
        p.router.isEnabled = false
        p.click(160); p.click(540); p.down(300)
        #expect(p.previous == 0 && p.links.isEmpty && p.drags == 0)
    }

    @Test func linkOnlyWithinVisibleBandNotUnderControlStrip() {
        let p = Probe()
        p.router.hitItems = { [HitItem(seq: 3, visualLeft: 130, width: 200, hasLinkSlot: true)] }   // 欄位 554..<580 → 在可視帶子 [250, 620) 內
        p.click(570)
        #expect(p.links == [3])
        p.router.hitItems = { [HitItem(seq: 4, visualLeft: -150, width: 100, hasLinkSlot: true)] }  // 欄位 174..<200 → 被控制列（標籤右側）蓋住
        p.click(185)
        #expect(p.links == [3] && p.previous == 0 && p.next == 0, "被控制列蓋住的迴紋針無效，且 185 在位置指示（拖曳）")
    }

    @Test func viewTrackingAreaIsAlwaysActiveEnterExit() {
        let v = TickerView(config: .provisional)
        v.updateTrackingAreas()
        #expect(v.trackingAreas.count == 1)
        let o = v.trackingAreas[0].options
        #expect(o.contains(.activeAlways) && o.contains(.mouseEnteredAndExited) && o.contains(.inVisibleRect))
        v.updateTrackingAreas()
        #expect(v.trackingAreas.count == 1, "重複更新不累積追蹤區")
    }

    @Test func viewPointerCallbackReportsEnterAndExit() {
        let v = TickerView(config: .provisional)
        var got: [Bool] = []
        v.onPointerInside = { got.append($0) }
        v.pointerChanged(true); v.pointerChanged(false)
        #expect(got == [true, false])
    }
}
