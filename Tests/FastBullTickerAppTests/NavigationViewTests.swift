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
    /// 面板 648×42、齒輪槽 0..<28、標籤 28..<178、控制列 178..<278（`<` 178..<202、指示 202..<254、`>` 254..<278）、帶子 278..<648；一則有連結的訊息：視覺左緣 100、寬 200 → 連結欄位 552..<578。
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
        p.down(188)
        #expect(p.previous == 0 && p.drags == 0, "按下時不觸發、也不拖曳")
        p.up(188)
        #expect(p.previous == 1 && p.next == 0)
        p.click(268)
        #expect(p.next == 1)
    }

    @Test func linkFiresOnMouseUpWithItsSeq() {
        let p = Probe()
        p.down(568)
        #expect(p.links.isEmpty)
        p.up(568)
        #expect(p.links == [7] && p.drags == 0)
    }

    @Test func releasingOutsideThePressedTargetDoesNotFire() {
        let p = Probe()
        p.down(188); p.up(268)            // 在 < 按下、移到 > 放開
        p.down(188); p.up(300)            // 移到帶子放開
        p.down(568); p.up(300)            // 迴紋針按下、移開放開
        p.down(568); p.up(188)
        #expect(p.previous == 0 && p.next == 0 && p.links.isEmpty)
    }

    @Test func mouseUpWithoutMatchingMouseDownDoesNothing() {
        let p = Probe()
        p.up(188); p.up(568)
        #expect(p.previous == 0 && p.links.isEmpty)
    }

    @Test func rightAndOtherButtonsNeverTrigger() {
        let p = Probe()
        for b in [PointerButton.right, .other] {
            p.down(188, button: b); p.up(188, button: b)
            p.down(568, button: b); p.up(568, button: b)
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
        p.down(228)                       // 位置指示（不是按鈕）
        #expect(p.drags == 3)
        p.down(188); p.down(568)          // 按鈕、迴紋針：不拖曳
        #expect(p.drags == 3)
    }

    @Test func dragThenReleaseOverButtonDoesNotFire() {
        let p = Probe()
        p.down(300)                       // 拖曳開始
        p.up(188)
        #expect(p.previous == 0)
    }

    @Test func disabledRouterIgnoresEverything() {
        let p = Probe()
        p.router.isEnabled = false
        p.click(188); p.click(568); p.down(300)
        #expect(p.previous == 0 && p.links.isEmpty && p.drags == 0)
    }

    @Test func linkOnlyWithinVisibleBandNotUnderControlStrip() {
        let p = Probe()
        p.router.hitItems = { [HitItem(seq: 3, visualLeft: 130, width: 200, hasLinkSlot: true)] }   // 欄位 582..<608 → 在可視帶子 [278, 648) 內
        p.click(598)
        #expect(p.links == [3])
        p.router.hitItems = { [HitItem(seq: 4, visualLeft: -150, width: 100, hasLinkSlot: true)] }  // 欄位 202..<228 → 被控制列（標籤右側）蓋住
        p.click(213)
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
