// 進入點：accessory App（無 Dock 圖示），組裝全在 FastBullTickerApp.AppDelegate。
// 永不呼叫任何 App 啟用 API（見 openspec app-shell／panel-shell）。
import AppKit
import FastBullTickerApp

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
