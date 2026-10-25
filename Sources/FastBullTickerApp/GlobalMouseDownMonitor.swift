import AppKit

/// 可注入的「滑鼠按下」監看器（settings-gear task 9）。處理函式收到按下當下的螢幕座標（Cocoa 座標）。
@MainActor
public protocol MouseDownMonitoring: AnyObject {
    var isInstalled: Bool { get }
    /// 安裝（已安裝則先移除再裝，不會重複）。
    func install(_ handler: @escaping (CGPoint) -> Void)
    func remove()
}

/// 真實的全域滑鼠按下監看器：只監看左右鍵按下，**不需要輔助使用權限**（鍵盤事件才需要），也不監看鍵盤。
/// 全域監看器收不到本 App 自己視窗內的事件；面板內與跑馬燈上的點擊由本地命中測試處理。
/// 自動測試只檢查 `eventMask` 與未安裝狀態，**從不呼叫 `install`**。
@MainActor
public final class GlobalMouseDownMonitor: MouseDownMonitoring {
    public static let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    private var token: Any?
    public init() {}

    public var isInstalled: Bool { token != nil }

    public func install(_ handler: @escaping (CGPoint) -> Void) {
        remove()
        token = NSEvent.addGlobalMonitorForEvents(matching: Self.eventMask) { _ in
            let p = NSEvent.mouseLocation
            if Thread.isMainThread { MainActor.assumeIsolated { handler(p) } }
            else { DispatchQueue.main.async { handler(p) } }
        }
    }

    public func remove() {
        if let t = token { NSEvent.removeMonitor(t); token = nil }
    }
}
