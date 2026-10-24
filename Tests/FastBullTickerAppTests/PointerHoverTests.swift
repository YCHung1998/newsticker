import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp

@Suite struct PointerHoverTests {
    private let frame = CGRect(x: 100, y: 800, width: 620, height: 42)

    @Test func insideAndOutside() {
        #expect(PointerHover.isInside(mouse: CGPoint(x: 400, y: 820), panelFrame: frame, panelVisible: true))
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 99, y: 820), panelFrame: frame, panelVisible: true))
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 400, y: 843), panelFrame: frame, panelVisible: true))
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 400, y: 799), panelFrame: frame, panelVisible: true))
    }

    @Test func edgesAreHalfOpen() {
        #expect(PointerHover.isInside(mouse: CGPoint(x: 100, y: 800), panelFrame: frame, panelVisible: true))
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 720, y: 820), panelFrame: frame, panelVisible: true))
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 400, y: 842), panelFrame: frame, panelVisible: true))
    }

    @Test func hiddenPanelCountsAsOutside() {
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 400, y: 820), panelFrame: frame, panelVisible: false))
    }

    @Test func clickThroughNeverPauses() {
        #expect(!PointerHover.isInside(mouse: CGPoint(x: 400, y: 820), panelFrame: frame, panelVisible: true, clickThrough: true))
    }

    @Test func reconcileOverridesLostExitEvent() {
        // 事件說「在內」，核對說「在外」→ 以核對為準
        #expect(PointerHover.reconciled(tracked: true, mouse: CGPoint(x: 0, y: 0), panelFrame: frame, panelVisible: true) == false)
        #expect(PointerHover.reconciled(tracked: false, mouse: CGPoint(x: 400, y: 820), panelFrame: frame, panelVisible: true) == true)
        #expect(PointerHover.reconciled(tracked: true, mouse: CGPoint(x: 400, y: 820), panelFrame: frame, panelVisible: false) == false)
    }
}
