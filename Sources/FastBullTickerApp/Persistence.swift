import Foundation
import CoreGraphics
import AppKit

/// 螢幕資訊（純值，供純函式與測試）。`uuid` 來自 `CGDisplayCreateUUIDFromDisplayID`。
public struct ScreenInfo: Equatable, Sendable {
    public var uuid: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    public init(uuid: String, frame: CGRect, visibleFrame: CGRect) {
        self.uuid = uuid; self.frame = frame; self.visibleFrame = visibleFrame
    }

    /// 目前系統的螢幕；第一個為主螢幕（有選單列者）。
    @MainActor public static func current() -> [ScreenInfo] {
        NSScreen.screens.map { s in
            var uuid = ""
            if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               let cf = CGDisplayCreateUUIDFromDisplayID(num.uint32Value)?.takeRetainedValue(),
               let str = CFUUIDCreateString(nil, cf) as String? { uuid = str }
            return ScreenInfo(uuid: uuid, frame: s.frame, visibleFrame: s.visibleFrame)
        }
    }
}

/// 面板位置：所在螢幕 UUID＋相對該螢幕 `frame.origin` 的偏移。
public struct PanelPlacement: Equatable, Sendable, Codable {
    public var screenUUID: String
    public var offsetX: Double
    public var offsetY: Double
    public init(screenUUID: String, offsetX: Double, offsetY: Double) {
        self.screenUUID = screenUUID; self.offsetX = offsetX; self.offsetY = offsetY
    }
}

public enum PlacementMath {
    /// 夾制：把 `frame` 放進 `visible` 內（放得下就完整放入；放不下則貼左／上緣）。純函式。
    public static func clamp(_ frame: CGRect, into visible: CGRect) -> CGRect {
        var f = frame
        f.origin.x = frame.width <= visible.width ? min(max(frame.minX, visible.minX), visible.maxX - frame.width) : visible.minX
        f.origin.y = frame.height <= visible.height ? min(max(frame.minY, visible.minY), visible.maxY - frame.height) : visible.maxY - frame.height
        return f
    }

    /// 還原：找得到存檔螢幕就用它，否則退回主螢幕（`screens.first`）；結果夾在該螢幕可視區內。
    public static func restore(_ saved: PanelPlacement?, size: CGSize, screens: [ScreenInfo], defaultMargin: CGFloat = 8) -> CGRect? {
        guard let primary = screens.first else { return nil }
        guard let saved else {
            // 無存檔：主螢幕可視區上緣置中。
            let vf = primary.visibleFrame
            let f = CGRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - defaultMargin, width: size.width, height: size.height)
            return clamp(f, into: vf)
        }
        let screen = screens.first { $0.uuid == saved.screenUUID } ?? primary
        let f = CGRect(x: screen.frame.minX + saved.offsetX, y: screen.frame.minY + saved.offsetY, width: size.width, height: size.height)
        return clamp(f, into: screen.visibleFrame)
    }

    /// 由目前 frame 推出存檔位置：以重疊面積最大的螢幕為準，無重疊退回主螢幕。
    public static func placement(for frame: CGRect, screens: [ScreenInfo]) -> PanelPlacement? {
        guard let primary = screens.first else { return nil }
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let best = screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) } ?? primary
        let screen = area(best.frame.intersection(frame)) > 0 ? best : primary
        return PanelPlacement(screenUUID: screen.uuid, offsetX: frame.minX - screen.frame.minX, offsetY: frame.minY - screen.frame.minY)
    }

    /// 螢幕參數變更後重新夾制：以目前 frame 重疊最大的螢幕（沒有則主螢幕）的可視區為準。
    public static func reclamp(_ frame: CGRect, screens: [ScreenInfo]) -> CGRect? {
        guard let primary = screens.first else { return nil }
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
        let best = screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) } ?? primary
        let screen = area(best.frame.intersection(frame)) > 0 ? best : primary
        return clamp(frame, into: screen.visibleFrame)
    }
}

/// 存取媒介（可注入）。點穿狀態不在此介面內，故無法被持久化（task 3.3）。
public protocol PersistenceStore: AnyObject {
    func loadPlacement() -> PanelPlacement?
    func savePlacement(_ p: PanelPlacement)
    func loadAlpha() -> Double?
    func saveAlpha(_ a: Double)
}

/// UserDefaults 實作；suite 可注入。儲存媒介為 UserDefaults【假設】。
public final class UserDefaultsStore: PersistenceStore {
    private let defaults: UserDefaults
    static let placementKey = "panel.placement"
    static let alphaKey = "panel.alpha"
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func loadPlacement() -> PanelPlacement? {
        guard let d = defaults.data(forKey: Self.placementKey) else { return nil }
        return try? JSONDecoder().decode(PanelPlacement.self, from: d)
    }
    public func savePlacement(_ p: PanelPlacement) {
        if let d = try? JSONEncoder().encode(p) { defaults.set(d, forKey: Self.placementKey) }
    }
    public func loadAlpha() -> Double? { defaults.object(forKey: Self.alphaKey) as? Double }
    public func saveAlpha(_ a: Double) { defaults.set(a, forKey: Self.alphaKey) }
}

/// 位置存檔的 debounce：連續 `noteMoved` 合併成一次寫入（以注入時鐘計時）。
public final class PlacementSaver: @unchecked Sendable {
    private let store: PersistenceStore
    private let clock: FeedClock
    private let queue: DispatchQueue
    private let delay: TimeInterval
    private let screens: @Sendable () -> [ScreenInfo]
    private let lock = NSLock()
    private var timer: FeedTimer?
    private var pending: CGRect?
    public private(set) var writeCount = 0

    public init(store: PersistenceStore, clock: FeedClock = SystemFeedClock(), queue: DispatchQueue = .main,
                delay: TimeInterval, screens: @escaping @Sendable () -> [ScreenInfo]) {
        self.store = store; self.clock = clock; self.queue = queue; self.delay = delay; self.screens = screens
    }

    /// 每次 `didMoveNotification` 呼叫；只保留最後的 frame，重新起算 debounce。
    public func noteMoved(_ frame: CGRect) {
        lock.lock(); defer { lock.unlock() }
        pending = frame
        timer?.cancel()
        timer = clock.schedule(after: delay, on: queue) { [weak self] in self?.flush() }
    }

    private func flush() {
        lock.lock()
        let frame = pending; pending = nil; timer = nil
        lock.unlock()
        guard let frame, let p = PlacementMath.placement(for: frame, screens: screens()) else { return }
        store.savePlacement(p)
        lock.lock(); writeCount += 1; lock.unlock()
    }
}
