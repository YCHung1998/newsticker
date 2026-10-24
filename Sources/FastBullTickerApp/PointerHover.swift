import CoreGraphics

/// 指標是否在面板內（純函式）。供補料計時器以 `NSEvent.mouseLocation` 與 `panel.frame`（同為螢幕座標）核對，
/// 避免 mouse-exited 事件遺失造成永久凍結。隱藏面板與點穿模式一律視為「在外」（不暫停）。
public enum PointerHover {
    public static func isInside(mouse: CGPoint, panelFrame: CGRect, panelVisible: Bool, clickThrough: Bool = false) -> Bool {
        guard panelVisible, !clickThrough else { return false }
        return panelFrame.contains(mouse)       // CGRect.contains：min 含、max 不含
    }

    /// 事件追蹤的狀態與核對結果不一致時，以核對為準。
    public static func reconciled(tracked: Bool, mouse: CGPoint, panelFrame: CGRect, panelVisible: Bool,
                                  clickThrough: Bool = false) -> Bool {
        _ = tracked
        return isInside(mouse: mouse, panelFrame: panelFrame, panelVisible: panelVisible, clickThrough: clickThrough)
    }
}
