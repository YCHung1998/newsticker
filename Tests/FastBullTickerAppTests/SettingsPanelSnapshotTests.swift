import Testing
import AppKit
@testable import FastBullTickerApp

fileprivate typealias TickerStyle = FastBullTickerApp.TickerStyle

// settings-gear task 8：離屏渲染設定面板（不顯示視窗；內容放進從未 order 的 SettingsPanel，用 cacheDisplay 畫成點陣圖）。
// **非實機畫面**：離屏渲染不等於螢幕上的實機合成與互動。只有設定 GB_SNAPSHOT_DIR 才寫 PNG。執行：swift test --filter SettingsPanelSnapshot
@MainActor
@Suite struct SettingsPanelSnapshotTests {
    private func render(style: TickerStyle = .default, problem: Bool = false, launch: LaunchAtLoginViewState) throws -> (content: SettingsPanelContentView, rep: NSBitmapImageRep) {
        _ = NSApplication.shared
        let content = SettingsPanelContentView()
        let panel = SettingsPanel(config: .provisional, content: content)      // 只當宿主，從不顯示
        content.reload(SettingsPanelModel.items(style: style, hasConfigProblem: problem, launch: launch))
        let size = content.contentSize
        panel.setFrame(CGRect(origin: .zero, size: size), display: false)
        content.frame = CGRect(origin: .zero, size: size)
        content.layoutSubtreeIfNeeded()
        let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        return (content, rep)
    }

    private func write(_ rep: NSBitmapImageRep, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["GB_SNAPSHOT_DIR"] else { return }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private let notRegistered = LaunchAtLoginViewState(isOn: false, detail: "未啟用", offersOpenSettings: false, isError: false)
    private let approval = LaunchAtLoginViewState(isOn: false, detail: "需要在「系統設定 → 一般 → 登入項目」核准", offersOpenSettings: true, isError: false)
    private let failed = LaunchAtLoginViewState(isOn: false, detail: "失敗：Operation not permitted", offersOpenSettings: false, isError: true)

    private func allControlsFit(_ c: SettingsPanelContentView) -> Bool {
        let b = c.bounds
        func fits(_ v: NSView?) -> Bool { guard let v else { return true }; return b.contains(c.convert(v.bounds, from: v)) }
        let ids = ["fontSize", "replayCount", "liveColors", "pollInterval"]
        return ids.allSatisfy { fits(c.segmented($0)) }
            && ["scrollSpeed", "cornerRadius", "seekHold"].allSatisfy { fits(c.slider($0)) }
            && ["showTime", "showLabel", "launchAtLogin"].allSatisfy { fits(c.toggle($0)) }
            && ["openFile", "reset", "close", "openLoginSettings"].allSatisfy { fits(c.button($0)) }
    }

    private func nonBlank(_ rep: NSBitmapImageRep) -> Int {
        var distinct = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) { for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            distinct.insert(UInt32((c?.redComponent ?? 0) * 255) << 16 | UInt32((c?.greenComponent ?? 0) * 255) << 8 | UInt32((c?.blueComponent ?? 0) * 255))
        } }
        return distinct.count
    }

    @Test func defaultPanelRendersWithEveryControlInsideTheBounds() throws {
        let (c, rep) = try render(launch: notRegistered)
        #expect(c.contentSize.width == 330 && c.contentSize.height > 250 && c.contentSize.height < 700, "高度 \(c.contentSize.height)")
        #expect(allControlsFit(c))
        #expect(nonBlank(rep) > 8, "不是一張空白圖")
        try write(rep, "gb-settings-default")
    }

    @Test func approvalStateShowsTheOpenSettingsButtonAndIsTaller() throws {
        let (d, _) = try render(launch: notRegistered)
        let (c, rep) = try render(launch: approval)
        #expect(c.button("openLoginSettings") != nil && allControlsFit(c))
        #expect(c.contentSize.height > d.contentSize.height)
        try write(rep, "gb-settings-approval")
    }

    @Test func errorStateShowsTheConfigNoticeAndTheFailureText() throws {
        var s = TickerStyle.default; s.fontSize = 20; s.scrollSpeed = 180; s.cornerRadius = 8; s.seekHoldSeconds = 3; s.pollIntervalSeconds = 30
        let (c, rep) = try render(style: s, problem: true, launch: failed)
        #expect(c.noticeText == "設定檔有誤，沿用上次有效值" && c.detailText == "失敗：Operation not permitted" && allControlsFit(c))
        try write(rep, "gb-settings-error")
    }
}
