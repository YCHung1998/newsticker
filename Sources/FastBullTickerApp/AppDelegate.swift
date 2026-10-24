import AppKit
import FastBullTickerCore

/// 組裝（task 4.2）：FeedClient → Core → TickerScheduler → TickerRenderer／PanelShell／StatusMenu。
/// 永不呼叫任何 App 啟用 API。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: ShellConfig
    private let environment: [String: String]
    private let log: AppLog
    private var panel: PanelShell?
    private var view: TickerView?
    private var menu: StatusMenuController?
    private var driver: TickerDriver?
    private var coordinator: AppCoordinator?
    private var feed: FeedClient?
    private var wake: WakeObserver?
    private var saver: PlacementSaver?
    private var store: UserDefaultsStore?
    private var feedTimer: Timer?
    private var statsTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init(config: ShellConfig = .provisional,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.config = config; self.environment = environment
        self.log = AppLog(fileURL: AppLog.defaultFileURL(environment: environment))
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        log.write("launch: FastBullTicker (config provisional: level=statusBar renderer=\(config.renderer.rawValue) feedTimer=\(config.feedTimer.rawValue))")
        let store = UserDefaultsStore(defaults: .standard)
        self.store = store
        let alpha = config.clampAlpha(store.loadAlpha() ?? config.defaultAlpha)

        // 面板與帶子
        let frame = PlacementMath.restore(store.loadPlacement(), size: config.panelSize, screens: ScreenInfo.current(),
                                          defaultMargin: config.screenMargin)
            ?? CGRect(origin: CGPoint(x: 100, y: 100), size: config.panelSize)
        let panel = PanelShell(config: config, frame: frame)
        panel.alphaValue = CGFloat(alpha)
        let view = TickerView(config: config)
        panel.contentView = view
        self.panel = panel; self.view = view

        // Core 排程與驅動
        let scheduler = TickerScheduler(config: config.schedulerConfig(),
                                        clock: { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 },
                                        measurer: view.itemMeasurer)
        let driver = TickerDriver(scheduler: scheduler, renderer: view)
        let coordinator = AppCoordinator(driver: driver, log: log)
        self.driver = driver; self.coordinator = coordinator
        view.onFrame = { [weak self] in self?.step() }

        // 選單（選單列與面板右鍵共用）
        let menu = StatusMenuController(config: config, initialAlpha: alpha)
        menu.onAlphaChanged = { [weak self] a in self?.panel?.alphaValue = CGFloat(a); self?.store?.saveAlpha(a) }
        menu.onVisibilityChanged = { [weak self] hidden in
            guard let self else { return }
            if hidden { self.panel?.orderOut(nil) } else { self.panel?.present() }
            self.driver?.setUserHidden(hidden)
            self.log.write("menu: hidden=\(hidden)")
        }
        menu.onClickThroughChanged = { [weak self] on in self?.panel?.ignoresMouseEvents = on; self?.log.write("menu: clickThrough=\(on)") }
        menu.onQuit = { NSApp.terminate(nil) }
        menu.install()
        view.contextMenu = menu.menu
        self.menu = menu

        // 位置存檔（didMove＋debounce）與螢幕參數變更
        let saver = PlacementSaver(store: store, delay: config.persistDebounce, screens: { MainActor.assumeIsolated { ScreenInfo.current() } })
        self.saver = saver
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let f = panel?.frame else { return }
                saver.noteMoved(f)
            }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, let f = PlacementMath.reclamp(panel.frame, screens: ScreenInfo.current()) else { return }
                if f != panel.frame { panel.setFrame(f, display: true); self.log.write("screens changed: reclamped frame=\(NSStringFromRect(f))") }
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, !(self.menu?.isHidden ?? false) else { return }
                let visible = panel.occlusionState.contains(.visible)
                self.driver?.setOccluded(!visible)
                self.log.write("occlusion: visible=\(visible)")
            }
        })

        panel.present()
        log.write("panel effective: \(PanelSettings(panel: panel).summary)")

        // 補料計時器：.common mode，選單展開（event tracking）時仍觸發。
        let t = Timer(timeInterval: config.feedInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        feedTimer = t
        let st = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let c = self?.coordinator { c.log.write(c.statsLine) } }
        }
        RunLoop.main.add(st, forMode: .common)
        statsTimer = st

        startFeed(coordinator)

        if let s = environment["FASTBULL_TICKER_AUTOQUIT_SECONDS"], let secs = Double(s), secs > 0 {
            log.write("autoquit in \(secs)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { NSApp.terminate(nil) }
        }
    }

    private func step() {
        driver?.step()
        coordinator?.noteMode()
    }

    private func startFeed(_ coordinator: AppCoordinator) {
        guard let url = FeedClientConfig.resolveHelperURL(environment: environment) else {
            log.write("feed: helper not found (set \(FeedClientConfig.helperEnvironmentVariable) or use the bundled app)")
            return
        }
        log.write("feed: helper=\(url.path)")
        let client = FeedClient(config: FeedClientConfig(helperURL: url), onEvent: AppCoordinator.bridge(to: coordinator))
        feed = client
        wake = WakeObserver(client: client)
        client.start()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let feed else { return .terminateNow }
        log.write("quit: shutting down helper")
        // 實測：.terminateLater 搭配 DispatchQueue.main.async 回覆，App 不會結束（2026-10-24 真機日誌）。
        // 改為在主執行緒短暫等待 FeedClient 收尾（stdin EOF → 2s SIGTERM → 2s SIGKILL，最多約 6 秒）後直接結束。
        let sem = DispatchSemaphore(value: 0)
        let log = self.log
        feed.shutdown {
            log.write("quit: helper shutdown completed")
            sem.signal()
        }
        if sem.wait(timeout: .now() + 6) == .timedOut { log.write("quit: helper shutdown TIMED OUT") }
        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        feedTimer?.invalidate(); statsTimer?.invalidate(); view?.stop()
        if let c = coordinator { log.write("final " + c.statsLine) }
        log.write("terminate")
    }
}
