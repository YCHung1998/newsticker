import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp
import FastBullTickerCore

// settings-gear task 2：HitTarget.gear、優先序、mouse-up 觸發、hover。純函式與可直接呼叫的處理方法，不開視窗。
// 幾何（預設）：面板 648×42、齒輪槽 0..<28、標籤 28..<178、控制列 178..<278、帶子 278..<648。執行：swift test --filter GearHit
@MainActor
private final class GearProbe {
    var gear = 0, previous = 0, next = 0, links: [Int] = [], drags = 0
    let router: NavigationInputRouter
    init(geometry: HitGeometry = ShellConfig.provisional.hitGeometry, items: [HitItem] = []) {
        router = NavigationInputRouter(geometry: geometry)
        router.hitItems = { items }
        router.onGear = { [unowned self] in gear += 1 }
        router.onPrevious = { [unowned self] in previous += 1 }
        router.onNext = { [unowned self] in next += 1 }
        router.onLink = { [unowned self] in links.append($0) }
    }
    func down(_ x: Double, button: PointerButton = .left) { router.mouseDown(at: CGPoint(x: x, y: 21), button: button, performDrag: { self.drags += 1 }) }
    func up(_ x: Double, button: PointerButton = .left) { router.mouseUp(at: CGPoint(x: x, y: 21), button: button) }
}

@MainActor
@Suite struct GearHitTests {
    private let geo = ShellConfig.provisional.hitGeometry
    private func hit(_ x: Double, _ y: Double = 21, items: [HitItem] = [], in g: HitGeometry? = nil) -> HitTarget {
        HitTesting.target(at: CGPoint(x: x, y: y), in: g ?? geo, items: items)
    }

    @Test func gearSlotIsAHalfOpenRangeAtTheLeftEdge() {
        #expect(hit(0) == .gear && hit(14) == .gear && hit(27.9) == .gear)
        #expect(hit(28) == .drag, "標籤")
        #expect(hit(0, 0) == .gear && hit(0, 41.9) == .gear, "整條高度")
        #expect(hit(-0.1) == .drag, "面板外")
    }

    @Test func buttonsAreShiftedByTheGearSlot() {
        #expect(hit(178) == .previousButton && hit(201.9) == .previousButton)
        #expect(hit(202) == .drag && hit(253.9) == .drag)
        #expect(hit(254) == .nextButton && hit(277.9) == .nextButton)
        #expect(hit(177.9) == .drag, "標籤")
    }

    @Test func hiddenLabelStillHasGearAtLeft() {
        let g = ShellConfig.provisional.makeHitGeometry(showLabel: false)
        #expect(hit(10, in: g) == .gear && hit(40, in: g) == .previousButton && hit(100, in: g) == .drag && hit(110, in: g) == .nextButton)
    }

    @Test func gearBeatsLinkZoneBeneathIt() {
        // 連結欄位右緣 = 278 + visualLeft + width；讓區間 [右緣−30, 右緣+4) 蓋住齒輪槽
        let under = HitItem(seq: 3, visualLeft: -270, width: 10, hasLinkSlot: true)    // 右緣 18：區間 −12..<22
        #expect(hit(10, items: [under]) == .gear)
        #expect(hit(100, items: [under]) == .drag)
    }

    @Test func linksCoveredByGearLabelOrStripAreNeverLinks() {
        let covered = HitItem(seq: 4, visualLeft: -250, width: 100, hasLinkSlot: true)  // 右緣 128：區間 98..<132（標籤內）
        for x in stride(from: 0.0, to: 278, by: 3.5) {
            if case .link = hit(x, items: [covered]) { Issue.record("x=\(x) 不應是連結") }
        }
        #expect(hit(278, items: [HitItem(seq: 5, visualLeft: -10, width: 20, hasLinkSlot: true)]) == .link(seq: 5), "可視帶子起點之後仍有效")
    }

    @Test func gearFiresOnMouseUpOnlyAndNeverDrags() {
        let p = GearProbe()
        p.down(14)
        #expect(p.gear == 0 && p.drags == 0, "按下時不觸發、不拖曳")
        p.up(14)
        #expect(p.gear == 1 && p.drags == 0)
    }

    @Test func releasingOutsideTheGearDoesNotFire() {
        let p = GearProbe()
        p.down(14); p.up(100)            // 移到標籤放開
        p.down(14); p.up(200)            // 移到控制列
        p.down(100); p.up(14)            // 在標籤按下、移到齒輪放開
        #expect(p.gear == 0)
    }

    @Test func rightButtonAndClickThroughDoNotFire() {
        let p = GearProbe()
        p.down(14, button: .right); p.up(14, button: .right)
        p.down(14, button: .other); p.up(14, button: .other)
        #expect(p.gear == 0)
        p.router.isEnabled = false
        p.down(14); p.up(14)
        #expect(p.gear == 0 && p.drags == 0)
        p.router.isEnabled = true
        p.down(14); p.up(14)
        #expect(p.gear == 1)
    }

    @Test func clickThroughTurnedOnBetweenDownAndUpCancelsTheGear() {
        let p = GearProbe()
        p.down(14)
        p.router.isEnabled = false          // 按住期間開啟點穿模式
        p.up(14)
        #expect(p.gear == 0)
    }

    @Test func gearClickDoesNotTriggerOtherActions() {
        let p = GearProbe()
        p.down(14); p.up(14)
        p.down(190); p.up(190)
        #expect(p.gear == 1 && p.previous == 1 && p.next == 0 && p.links.isEmpty)
    }

    @Test func dragStillWorksOnLabelAndTape() {
        let p = GearProbe()
        p.down(100); p.up(100)
        p.down(400); p.up(400)
        #expect(p.drags == 2 && p.gear == 0)
    }

    // MARK: hover（TickerView；直接呼叫處理方法）

    @Test func hoverBrightensGearOnlyInsideTheSlotAndResetsOnExit() {
        let v = TickerView(config: .provisional)
        #expect(v.gearOpacity == TickerView.gearIdleOpacity && !v.isGearHovered)
        v.pointerMoved(to: CGPoint(x: 14, y: 21))
        #expect(v.isGearHovered && v.gearOpacity == TickerView.gearHoverOpacity)
        v.pointerMoved(to: CGPoint(x: 400, y: 21))
        #expect(!v.isGearHovered && v.gearOpacity == TickerView.gearIdleOpacity)
        v.pointerMoved(to: CGPoint(x: 5, y: 5))
        #expect(v.isGearHovered)
        v.pointerChanged(false)
        #expect(!v.isGearHovered && v.gearOpacity == TickerView.gearIdleOpacity, "離開面板復原")
    }

    @Test func hoverFollowsGeometryWhenLabelToggles() {
        var s = TickerStyle.default; s.showLabel = false
        let v = TickerView(config: .provisional, style: s)
        v.pointerMoved(to: CGPoint(x: 40, y: 21))
        #expect(!v.isGearHovered, "x=40 在控制列上，不在齒輪槽")
        v.pointerMoved(to: CGPoint(x: 10, y: 21))
        #expect(v.isGearHovered)
    }

    @Test func idleAndHoverOpacitiesAreDistinctAndValid() {
        #expect(TickerView.gearIdleOpacity < TickerView.gearHoverOpacity && TickerView.gearHoverOpacity == 1 && TickerView.gearIdleOpacity > 0.5)
    }
}
