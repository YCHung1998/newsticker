import AppKit
import FastBullTickerCore

/// 組裝（task 4.2）：FeedClient → Core → TickerScheduler → TickerRenderer／PanelShell／StatusMenu。
/// 永不呼叫任何 App 啟用 API（唯一例外：`SingleInstanceGuard.swift` 的重複實例對話框）。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config: ShellConfig
    private let environment: [String: String]
    private let log: AppLog
    private let instanceCheck: @MainActor ([String: String]) -> Bool   // true＝繼續啟動
    private var panel: PanelShell?
    private var view: TickerView?
    private var menu: StatusMenuController?
    private var driver: TickerDriver?
    private var coordinator: AppCoordinator?
    private var navigation: NavigationActions?
    private var styleStore: StyleStore?
    private var styleApplier: StyleApplier?
    private var styleRunner: StyleActionRunner?
    private var feed: FeedClient?
    private var wake: WakeObserver?
    private var saver: PlacementSaver?
    private var store: UserDefaultsStore?
    private var feedTimer: Timer?
    private var statsTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var occlusion: OcclusionDebouncer?
    private var logNextFrameAfterThaw = false

    public init(config: ShellConfig = .provisional,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                instanceCheck: (@MainActor ([String: String]) -> Bool)? = nil) {
        self.config = config; self.environment = environment
        self.instanceCheck = instanceCheck ?? { SingleInstanceGuard.makeSystem(environment: $0).run() == .proceed }
        self.log = AppLog(fileURL: AppLog.defaultFileURL(environment: environment))
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 單一實例檢查（single-instance）：必須早於面板、FeedClient／helper、pid 檔。
        // 此時 feed == nil，結束不會留下 helper。
        if !instanceCheck(environment) {
            log.write("single-instance: quitting this instance before starting helper")
            NSApp.terminate(nil)
            return
        }
        log.write("launch: FastBullTicker (config provisional: level=statusBar renderer=\(config.renderer.rawValue) feedTimer=\(config.feedTimer.rawValue))")
        let store = UserDefaultsStore(defaults: .standard)
        self.store = store
        let alpha = config.clampAlpha(store.loadAlpha() ?? config.defaultAlpha)

        // 樣式（ticker-style-settings 6.1）：先載入檔案（損壞或不存在 → 預設，保留檔案不動）；監看在接好回呼後才開始。
        let styleStore = StyleStore(fileURL: StyleStore.defaultFileURL(environment: environment), watcher: DispatchSourceStyleWatcher(), log: log)
        styleStore.load()
        self.styleStore = styleStore
        log.write("style: file=\(styleStore.fileURL.path)")

        // 面板與帶子（以預設樣式建構，隨後經與熱重載／選單相同的 `StyleApplier` 路徑套用目前樣式）
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

        // 導覽與連結：箭頭→seek、迴紋針→唯一的真實 opener（WorkspaceURLOpener）、指標進出→暫停捲動。
        let log = self.log
        let actions = NavigationActions(driver: driver, opener: WorkspaceURLOpener(onFailure: { log.write("nav: open failed: \($0.localizedDescription)") }), log: log)
        actions.bind(to: view.router)
        view.router.hitItems = { [weak driver] in driver?.hitItems() ?? [] }
        view.onPointerInside = { [weak self] inside in self?.driver?.setPointerInside(inside) }
        self.navigation = actions
        let applier = StyleApplier(config: config, view: view, driver: driver, log: log)
        self.styleApplier = applier
        applier.apply(styleStore.style, source: "startup")
        let viewport = config.tapeViewport(showLabel: styleStore.style.showLabel)
        self.log.write("layout: tapeViewport=\(Int(viewport)) controlStrip=\(Int(config.controlStripWidth)) linkSlot=\(Int(config.linkSlotWidth)) hitSlop=\(Int(config.hitSlop)) panel=\(Int(config.panelSize.width))x\(Int(config.panelSize.height))")
        self.log.write("style: effective \(styleStore.style.summary)")

        // 選單（選單列與面板右鍵共用）
        let menu = StatusMenuController(config: config, initialAlpha: alpha)
        menu.onAlphaChanged = { [weak self] a in self?.panel?.alphaValue = CGFloat(a); self?.store?.saveAlpha(a) }
        menu.onVisibilityChanged = { [weak self] hidden in
            guard let self else { return }
            if hidden { self.panel?.orderOut(nil) } else { self.panel?.present() }
            self.driver?.setUserHidden(hidden)
            self.log.write("menu: hidden=\(hidden)")
        }
        menu.onClickThroughChanged = { [weak self] on in self?.panel?.ignoresMouseEvents = on; self?.view?.router.isEnabled = !on; self?.log.write("menu: clickThrough=\(on)") }
        menu.onQuit = { NSApp.terminate(nil) }
        let runner = StyleActionRunner(store: styleStore, opener: WorkspaceFileOpener(onFailure: { log.write("style: open file failed: \($0.localizedDescription)") }), log: log)
        self.styleRunner = runner
        StyleWiring.connect(store: styleStore, applier: applier, menu: menu.styleMenu, runner: runner)
        styleStore.startWatching()
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
        // 遮蔽：原始狀態變化先經防抖器（吸收切換 Space 轉場的翻動）；凍結／解凍只動 driver，
        // 絕不重設 frame／alpha／layers，也不呼叫 orderFront*（避免任何「重新呈現」）。
        let debouncer = OcclusionDebouncer(confirmDelay: config.occludedConfirmDelay) { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .confirmedOccluded: self.driver?.setOccluded(true)
            case .thawed: self.logNextFrameAfterThaw = true; self.driver?.setOccluded(false)
            case .cancelled: break
            }
            self.log.write("occlusion: decision=\(decision) \(self.diagState())")
        }
        occlusion = debouncer
        view.onLinkPauseChange = { [weak self] paused in self?.log.write("displayLink: \(paused ? "paused" : "resumed")") }
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let visible = panel.occlusionState.contains(.visible)
                self.log.write("occlusion: raw visible=\(visible) state=\(panel.occlusionState.rawValue) userHidden=\(self.menu?.isHidden ?? false) \(self.diagState())")
                guard !(self.menu?.isHidden ?? false) else { return }   // 使用者手動隱藏時不處理遮蔽（維持既有行為）
                self.occlusion?.note(visible: visible)
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.log.write("space: activeSpaceDidChange \(self?.diagState() ?? "")") }
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

    /// 診斷快照：scheduler tape 時間與面板 frame／alpha（用於判斷凍結／解凍時有沒有跳動）。
    private func diagState() -> String {
        let tape = driver.map { String(format: "%.3f", $0.scheduler.tapeTime) } ?? "-"
        let off = driver.map { String(format: "%.1f", $0.scheduler.scrollOffset) } ?? "-"
        let f = panel.map { NSStringFromRect($0.frame) } ?? "-"
        let a = panel.map { String(format: "%.2f", Double($0.alphaValue)) } ?? "-"
        return "tape=\(tape) offset=\(off) frame=\(f) alpha=\(a)"
    }

    /// 以 `NSEvent.mouseLocation`（不需任何權限）核對指標是否在面板內，避免 exit 事件遺失造成永久凍結。
    private func reconcilePointer() {
        guard let panel, let driver else { return }
        driver.reconcilePointer(mouse: NSEvent.mouseLocation, panelFrame: panel.frame, panelVisible: panel.isVisible,
                                clickThrough: panel.ignoresMouseEvents)
    }

    private func step() {
        reconcilePointer()
        if logNextFrameAfterThaw {
            logNextFrameAfterThaw = false
            driver?.step()
            log.write("firstFrameAfterThaw: \(diagState())")
            coordinator?.noteMode()
            return
        }
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
        styleStore?.stopWatching()
        styleStore?.flushWrite()
        if let c = coordinator { log.write("final " + c.statsLine) }
        log.write("terminate")
    }
}
