import Foundation
import CoreGraphics

public enum PointerButton: Equatable, Sendable { case left, right, other }

/// 滑鼠事件分派（純邏輯，不依賴 `NSEvent`／視窗，可直接呼叫測試）。
/// - mouse-down：算出命中目標並記錄；只有 `.drag` 才呼叫 `performDrag`；按鈕與迴紋針只記錄。
/// - mouse-up：目標與按下時相同才觸發動作（齒輪→`onGear`、按鈕→`onPrevious`／`onNext`、迴紋針→`onLink(seq)`、✕→`onQuit`）。
/// - 只處理左鍵；`isEnabled == false`（點穿模式）時全部忽略。
@MainActor
public final class NavigationInputRouter {
    public var geometry: HitGeometry
    public var hitItems: () -> [HitItem] = { [] }
    public var isEnabled = true {
        didSet { if oldValue != isEnabled { onEnabledChange?() } }
    }
    /// `isEnabled` 改變時呼叫（點穿模式切換）；`TickerView` 用它同步結束 ✕ 的顯示。
    public var onEnabledChange: (() -> Void)?
    public var onGear: () -> Void = {}
    public var onPrevious: () -> Void = {}
    public var onNext: () -> Void = {}
    public var onLink: (Int) -> Void = { _ in }
    public var onQuit: () -> Void = {}
    public private(set) var pressed: HitTarget?

    public init(geometry: HitGeometry) { self.geometry = geometry }

    /// 回傳命中目標；未處理（非左鍵、停用）回傳 nil。
    @discardableResult
    public func mouseDown(at point: CGPoint, button: PointerButton, performDrag: () -> Void) -> HitTarget? {
        pressed = nil
        guard isEnabled, button == .left else { return nil }
        let target = HitTesting.target(at: point, in: geometry, items: hitItems())
        if target == .drag { performDrag() } else { pressed = target }
        return target
    }

    /// 回傳是否觸發了動作。
    @discardableResult
    public func mouseUp(at point: CGPoint, button: PointerButton) -> Bool {
        defer { pressed = nil }
        guard isEnabled, button == .left, let down = pressed else { return false }
        let target = HitTesting.target(at: point, in: geometry, items: hitItems())
        guard target == down else { return false }
        switch target {
        case .gear: onGear()
        case .previousButton: onPrevious()
        case .nextButton: onNext()
        case .link(let seq): onLink(seq)
        case .quit: onQuit()
        case .drag: return false
        }
        return true
    }
}
