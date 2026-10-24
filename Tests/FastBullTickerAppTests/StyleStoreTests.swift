import Testing
import Foundation
@testable import FastBullTickerApp

// ticker-style-settings 3.1：StyleStore。執行：swift test --filter StyleStoreTests
// 全部使用暫存目錄＋假監看器＋假時鐘（Support.swift 的 FakeClock）；絕不讀寫使用者真實的 style.json。

final class FakeStyleWatcher: StyleFileWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private(set) var directory: URL?
    private(set) var startCount = 0
    func start(directory: URL, onChange: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock { handler = onChange; self.directory = directory; startCount += 1 }
        return true
    }
    func stop() { lock.withLock { handler = nil } }
    /// 測試明確呼叫以模擬一次目錄事件。
    func fire() { let h = lock.withLock { handler }; h?() }
    var isWatching: Bool { lock.withLock { handler != nil } }
}

final class ChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(TickerStyle, StyleChangeSource)] = []
    func add(_ s: TickerStyle, _ src: StyleChangeSource) { lock.withLock { items.append((s, src)) } }
    var count: Int { lock.withLock { items.count } }
    var sources: [StyleChangeSource] { lock.withLock { items.map(\.1) } }
    var styles: [TickerStyle] { lock.withLock { items.map(\.0) } }
}

/// 記錄檔案系統操作順序（包著真的磁碟實作）。
final class RecordingFS: StyleFileSystem, @unchecked Sendable {
    private let disk = DiskStyleFileSystem()
    private let lock = NSLock()
    private var _ops: [String] = []
    var failReplace = false
    var ops: [String] { lock.withLock { _ops } }
    private func rec(_ s: String) { lock.withLock { _ops.append(s) } }
    func read(_ url: URL, limit: Int) throws -> Data? { rec("read"); return try disk.read(url, limit: limit) }
    func createDirectory(_ url: URL) throws { rec("createDirectory"); try disk.createDirectory(url) }
    func writeTemporary(_ data: Data, besides url: URL) throws -> URL {
        let t = try disk.writeTemporary(data, besides: url); rec("writeTemporary:\(t.lastPathComponent)"); return t
    }
    func replace(_ url: URL, with temp: URL) throws {
        rec("replace:\(temp.lastPathComponent)")
        if failReplace { throw CocoaError(.fileWriteOutOfSpace) }
        try disk.replace(url, with: temp)
    }
    func copy(_ src: URL, to dst: URL) throws { rec("copy:\(dst.lastPathComponent)"); try disk.copy(src, to: dst) }
    func remove(_ url: URL) { rec("remove"); disk.remove(url) }
}

/// 一個完整的測試環境：暫存目錄、假監看器、假時鐘、私有序列佇列。
final class StyleEnv {
    let dir: URL
    let file: URL
    let watcher = FakeStyleWatcher()
    let clock = FakeClock()
    let queue = DispatchQueue(label: "StyleStoreTests")
    let log = AppLog(fileURL: nil, toStderr: false)
    let changes = ChangeLog()
    let fs = RecordingFS()
    let store: StyleStore

    init(subdirectory: String? = nil) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stylestore-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        dir = root
        let target = subdirectory.map { root.appendingPathComponent($0) } ?? root
        file = target.appendingPathComponent("style.json")
        precondition(file.path.hasPrefix(FileManager.default.temporaryDirectory.path), "測試只能使用暫存目錄")
        store = StyleStore(fileURL: file, watcher: watcher, clock: clock, queue: queue, fileSystem: fs, log: log)
        store.onChange = { [changes] s, src in changes.add(s, src) }
    }
    deinit {
        chmod(dir.path, 0o755)
        try? FileManager.default.removeItem(at: dir)
    }

    func put(_ json: String) { try! Data(json.utf8).write(to: file) }
    func putData(_ d: Data) { try! d.write(to: file) }
    var bytes: Data? { try? Data(contentsOf: file) }
    var bakBytes: Data? { try? Data(contentsOf: store.backupURL) }
    var listing: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? []).sorted() }
    /// 模擬目錄事件並走完 debounce。
    func fireAndSettle() { watcher.fire(); clock.advance(by: StyleStore.reloadDebounce + 0.01) }
    func settleWrite() { clock.advance(by: StyleStore.writeDebounce + 0.01) }
    var logs: [String] { log.recorded }
}

@Suite struct StyleStoreLoadTests {
    @Test func noFileGivesDefaultAndDoesNotCreateFile() {
        let e = StyleEnv()
        e.store.start()
        #expect(e.store.style == .default && !e.store.hasConfigProblem)
        #expect(e.listing.isEmpty, "啟動不自動建立檔案")
        #expect(e.watcher.directory?.path == e.dir.path && e.watcher.isWatching)
        #expect(e.store.writeCount == 0 && e.changes.count == 0)
    }

    @Test func corruptFileGivesDefaultKeepsFileAndFlagsProblem() {
        let e = StyleEnv()
        e.put("{ \"fontSize\": ")
        let before = e.bytes
        e.store.start()
        #expect(e.store.style == .default && e.store.hasConfigProblem)
        #expect(e.bytes == before, "不得修改或刪除該檔案")
        #expect(e.logs.contains { $0.hasPrefix("style: error") })
        #expect(e.listing == ["style.json"])
    }

    @Test func partialOutOfRangeFieldsAreClampedAndLogged() {
        let e = StyleEnv()
        e.put(##"{"fontSize": 99, "scrollSpeed": 120}"##)
        let before = e.bytes
        e.store.start()
        #expect(e.store.style.fontSize == 26 && e.store.style.scrollSpeed == 120 && !e.store.hasConfigProblem)
        #expect(e.logs.contains { $0.hasPrefix("style: warning fontSize") })
        #expect(e.bytes == before && e.store.writeCount == 0, "載入不改寫檔案")
        #expect(e.listing == ["style.json"])
    }

    @Test func oversizeFileIsTreatedAsUnreadable() {
        let e = StyleEnv()
        e.putData(Data(repeating: 0x20, count: StyleRanges.maxFileBytes + 5000))
        e.store.start()
        #expect(e.store.style == .default)
        if case .tooLarge = e.store.configProblem {} else { Issue.record("應為 tooLarge：\(String(describing: e.store.configProblem))") }
    }

    @Test func allLogLinesStartWithStylePrefix() {
        let e = StyleEnv()
        e.put(##"{"fontSize": 99, "x": 1}"##)
        e.store.start()
        e.put("{")
        e.fireAndSettle()
        e.store.update { $0.fontSize = 18 }
        e.settleWrite()
        #expect(!e.logs.isEmpty && e.logs.allSatisfy { $0.hasPrefix("style:") })
    }

    @Test func environmentVariableOverridesPath() {
        let home = URL(fileURLWithPath: "/nonexistent-home-for-test")
        let d = StyleStore.defaultFileURL(environment: [:], home: home)
        #expect(d.path == "/nonexistent-home-for-test/Library/Application Support/FastBullTicker/style.json")
        #expect(StyleStore.defaultFileURL(environment: ["FASTBULL_TICKER_STYLE": "/tmp/custom/s.json"], home: home).path == "/tmp/custom/s.json")
        #expect(StyleStore.defaultFileURL(environment: ["FASTBULL_TICKER_STYLE": ""], home: home) == d, "空字串視為未設定")
        #expect(StyleStore.environmentKey == "FASTBULL_TICKER_STYLE")
    }

    @Test func overriddenPathIsTheOnlyFileTouched() {
        let e = StyleEnv(subdirectory: "nested/deeper")
        e.store.start()
        e.store.update { $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.store.fileURL == e.file && FileManager.default.fileExists(atPath: e.file.path), "目錄不存在時會建立")
        #expect(e.watcher.directory?.path == e.file.deletingLastPathComponent().path)
    }
}

@Suite struct StyleStoreHotReloadTests {
    private func started(_ json: String? = nil) -> StyleEnv {
        let e = StyleEnv()
        if let json { e.put(json) }
        e.store.start()
        return e
    }

    @Test func editAppliesAfterDebounceExactlyOnce() {
        let e = started(##"{"fontSize": 16}"##)
        e.put(##"{"fontSize": 20}"##)
        e.watcher.fire()
        e.clock.advance(by: 0.1)
        #expect(e.store.style.fontSize == 16 && e.changes.count == 0, "debounce 內不套用")
        e.clock.advance(by: 0.3)
        #expect(e.store.style.fontSize == 20 && e.changes.count == 1 && e.changes.sources == [.file])
        #expect(e.changes.styles[0].fontSize == 20)
        #expect(e.store.writeCount == 0, "熱重載不寫檔")
    }

    @Test func burstOfFiftyEventsCoalescesToOneRead() {
        let e = started("{}")
        let parsesBefore = e.store.parseCount
        e.put(##"{"fontSize": 22}"##)
        for _ in 0..<50 { e.watcher.fire(); e.clock.advance(by: 0.002) }
        e.clock.advance(by: 0.4)
        #expect(e.store.parseCount == parsesBefore + 1 && e.changes.count == 1 && e.store.style.fontSize == 22)
    }

    @Test func identicalBytesAreNotReparsedOrReapplied() {
        let e = started(##"{"fontSize": 20}"##)
        let parses = e.store.parseCount
        e.fireAndSettle(); e.fireAndSettle()
        #expect(e.store.parseCount == parses && e.changes.count == 0)
    }

    @Test func differentBytesButEqualStyleParsesButDoesNotNotify() {
        let e = started(##"{"fontSize": 20}"##)
        e.put("{\n  \"fontSize\": 20,\n  \"showTime\": true\n}\n")
        let parses = e.store.parseCount
        e.fireAndSettle()
        #expect(e.store.parseCount == parses + 1 && e.changes.count == 0)
    }

    @Test func atomicReplaceByRenameIsStillDetected() throws {
        let e = started(##"{"fontSize": 14}"##)
        // 編輯器式儲存：寫暫存檔再改名覆蓋（原檔案的 inode 換了）
        let tmp = e.dir.appendingPathComponent("style.json.sb-1234")
        try Data(##"{"fontSize": 24}"##.utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(e.file, withItemAt: tmp)
        e.fireAndSettle()
        #expect(e.store.style.fontSize == 24 && e.changes.count == 1)
    }

    @Test func deletedFileKeepsEffectiveStyleAndLogs() throws {
        let e = started(##"{"fontSize": 20}"##)
        try FileManager.default.removeItem(at: e.file)
        e.fireAndSettle()
        #expect(e.store.style.fontSize == 20 && e.changes.count == 0)
        #expect(e.logs.contains { $0.contains("已被刪除") })
        e.put(##"{"fontSize": 20}"##)       // 又出現且內容相同：不通知
        e.fireAndSettle()
        #expect(e.changes.count == 0)
    }

    @Test func syntaxErrorKeepsOldValueThenRecovers() {
        let e = started(##"{"fontSize": 20}"##)
        e.put("{\"fontSize\": 20, ")
        e.fireAndSettle()
        #expect(e.store.style.fontSize == 20 && e.changes.count == 0 && e.store.hasConfigProblem)
        #expect(e.logs.contains { $0.hasPrefix("style: error") })
        e.put(##"{"fontSize": 18}"##)
        e.fireAndSettle()
        #expect(e.store.style.fontSize == 18 && !e.store.hasConfigProblem && e.changes.count == 1)
    }

    @Test func wholeFileFailureKindsAllKeepOldValue() {
        for bad in ["[]", "42", ##"{"version": 2}"##, ##"{"version": "1"}"##] {
            let e = started(##"{"fontSize": 20}"##)
            e.put(bad); e.fireAndSettle()
            #expect(e.store.style.fontSize == 20 && e.store.hasConfigProblem && e.changes.count == 0, "\(bad)")
        }
        let e = started(##"{"fontSize": 20}"##)
        e.putData(Data([0xFF, 0xFE, 0x00])); e.fireAndSettle()
        #expect(e.store.style.fontSize == 20 && e.store.hasConfigProblem)
    }

    @Test func fieldLevelErrorUsesFieldDefaultAndAppliesRest() {
        let e = started(##"{"liveBackground": "#FFE45C"}"##)
        e.put(##"{"liveBackground": "blue", "fontSize": 19}"##)
        e.fireAndSettle()
        #expect(e.store.style.liveBackground.hex == "#FFFFFF" && e.store.style.fontSize == 19)
        #expect(!e.store.hasConfigProblem && e.changes.count == 1)
        #expect(e.logs.contains { $0.hasPrefix("style: warning liveBackground") })
    }

    @Test func stopWatchingCancelsPendingReload() {
        let e = started("{}")
        e.put(##"{"fontSize": 20}"##)
        e.watcher.fire()
        e.store.stopWatching()
        e.clock.advance(by: 1)
        #expect(e.store.style.fontSize == 16 && e.changes.count == 0 && !e.watcher.isWatching)
    }
}

@Suite struct StyleStoreWriteBackTests {
    private func started(_ json: String? = nil) -> StyleEnv {
        let e = StyleEnv()
        if let json { e.put(json) }
        e.store.start()
        return e
    }

    @Test func sliderBurstAppliesEveryTimeButWritesOnce() {
        let e = started()
        for i in 1...50 { e.store.update { $0.cornerRadius = Double(i) * 0.4 }; e.clock.advance(by: 0.002) }
        #expect(e.changes.count == 50 && e.changes.sources.allSatisfy { $0 == .menu })
        #expect(e.bytes == nil, "debounce 內還沒寫")
        e.settleWrite()
        #expect(e.store.writeCount == 1)
        #expect(e.store.style.cornerRadius == 20)
        guard let b = e.bytes, case .success(let r) = StyleParser.parse(b) else { Issue.record("應寫出可解析的檔案"); return }
        #expect(r.style.cornerRadius == 20)
    }

    @Test func writeIsAtomicTempThenReplaceAndLeavesNoTemp() {
        let e = started(##"{"fontSize": 14}"##)
        e.store.update { $0.fontSize = 18 }
        e.settleWrite()
        let ops = e.fs.ops.drop { $0 != "createDirectory" }
        let names = ops.map { $0.split(separator: ":").first.map(String.init) ?? $0 }
        #expect(names.contains("writeTemporary") && names.contains("replace"))
        let ti = names.firstIndex(of: "writeTemporary")!, ri = names.firstIndex(of: "replace")!
        #expect(ti < ri, "先寫暫存檔再取代")
        let tempName = ops.first { $0.hasPrefix("writeTemporary:") }!.dropFirst("writeTemporary:".count)
        #expect(ops.contains("replace:\(tempName)") && tempName.hasPrefix(".style.json.tmp-"), "同目錄暫存檔")
        #expect(e.listing == ["style.json"], "沒有殘留暫存檔")
    }

    @Test func outputIsNormalizedJSON() {
        let e = started()
        e.store.update { $0.liveBackground = RGBColor(hex: "#ffe45c")!; $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.bytes == e.store.style.normalizedJSON())
        #expect(String(decoding: e.bytes ?? Data(), as: UTF8.self).contains("#FFE45C"))
    }

    @Test func backupsUnreadableOriginalBeforeOverwriting() {
        let garbage = "{ \"fontSize\": 14, // 我正在手寫\n"
        let e = started(garbage)
        #expect(e.store.hasConfigProblem)
        e.store.update { $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.bakBytes == Data(garbage.utf8), "原檔內容完整留在 .bak")
        guard let b = e.bytes, case .success(let r) = StyleParser.parse(b) else { Issue.record("新檔應合法"); return }
        #expect(r.style.fontSize == 20 && !e.store.hasConfigProblem)
        #expect(e.listing == ["style.json", "style.json.bak"])
    }

    @Test func backupsFileWithUnknownKeysAndDropsThemFromNewFile() {
        let original = ##"{"fontSize": 14, "myNote": "keep me"}"##
        let e = started(original)
        e.store.update { $0.showTime = false }
        e.settleWrite()
        #expect(e.bakBytes == Data(original.utf8))
        #expect(!String(decoding: e.bytes ?? Data(), as: UTF8.self).contains("myNote"))
    }

    @Test func backupsFileWhoseFieldsWouldBeRewrittenByClamping() {
        let original = ##"{"fontSize": 99}"##
        let e = started(original)
        e.store.update { $0.showTime = false }
        e.settleWrite()
        #expect(e.bakBytes == Data(original.utf8), "夾制會改變原值，先留備份（比規格最低要求多保護一種情況）")
    }

    @Test func noBackupWhenOriginalWasCleanOrMissing() {
        let e = started()                                     // 無檔案
        e.store.update { $0.fontSize = 18 }; e.settleWrite()
        e.store.update { $0.fontSize = 19 }; e.settleWrite()  // 原檔是我們自己寫的正規化輸出
        #expect(e.bakBytes == nil && e.store.writeCount == 2)
        let e2 = started(##"{"fontSize": 14}"##)             // 乾淨的手寫檔：沒有資訊會遺失
        e2.store.update { $0.fontSize = 18 }; e2.settleWrite()
        #expect(e2.bakBytes == nil)
    }

    @Test func ownWriteIsNotReappliedAndNotEvenReparsed() {
        let e = started()
        e.store.update { $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.store.writeCount == 1 && e.changes.count == 1)
        let parses = e.store.parseCount
        e.fireAndSettle()                                     // 寫入引起的目錄事件
        #expect(e.changes.count == 1, "不重套")
        #expect(e.store.parseCount == parses, "以內容比對辨識為自寫入，連解析都略過")
        #expect(e.store.writeCount == 1)
    }

    @Test func noOpUpdateDoesNothing() {
        let e = started()
        e.store.update { $0.fontSize = 16 }
        #expect(e.changes.count == 0 && e.clock.pendingTimerCount == 0 && !e.store.hasPendingWrite)
    }

    @Test func updateClampsToValidRange() {
        let e = started()
        e.store.update { $0.fontSize = 99; $0.replayCount = 1; $0.labelText = "  " }
        #expect(e.store.style.fontSize == 26 && e.store.style.replayCount == 3 && e.store.style.labelText == "即時財經快訊")
        #expect(e.store.style.isValid)
    }

    @Test func externalEditWinsOverPendingMenuWrite() {
        let e = started()
        e.store.update { $0.fontSize = 18 }                   // 待寫出
        e.put(##"{"fontSize": 25}"##)
        e.fireAndSettle()
        #expect(e.store.style.fontSize == 25 && e.changes.sources == [.menu, .file])
        e.clock.advance(by: 2)
        #expect(e.store.writeCount == 0, "較新的檔案內容勝出，丟棄待寫的選單變更")
        #expect(e.bytes == Data(##"{"fontSize": 25}"##.utf8))
    }

    @Test func writeFailureKeepsStyleAndDoesNotCrash() {
        let e = started()
        e.fs.failReplace = true
        e.store.update { $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.store.style.fontSize == 20 && e.store.lastWriteError != nil && e.store.writeCount == 0)
        #expect(e.logs.contains { $0.hasPrefix("style: error 寫入失敗") })
        #expect(e.listing.allSatisfy { !$0.hasPrefix(".style.json.tmp") }, "失敗後清掉暫存檔")
        e.fs.failReplace = false
        e.store.update { $0.fontSize = 21 }; e.settleWrite()
        #expect(e.store.writeCount == 1 && e.store.lastWriteError == nil, "之後可以恢復")
    }

    @Test func unwritableDirectoryDoesNotCrash() {
        let e = started()
        chmod(e.dir.path, 0o555)
        e.store.update { $0.fontSize = 20 }
        e.settleWrite()
        #expect(e.store.style.fontSize == 20 && e.store.lastWriteError != nil)
        chmod(e.dir.path, 0o755)
    }

    @Test func resetToDefaultBacksUpThenWritesDefault() {
        let original = ##"{"fontSize": 22, "liveBackground": "#FFE45C"}"##
        let e = started(original)
        #expect(e.store.style.fontSize == 22)
        e.store.resetToDefault()
        #expect(e.store.style == .default && e.changes.sources == [.menu])
        #expect(e.bakBytes == Data(original.utf8), "重設前的檔案內容留在 .bak")
        e.settleWrite()
        #expect(e.bytes == TickerStyle.default.normalizedJSON())
    }

    @Test func resetWhenNoFileMakesNoBackup() {
        let e = started()
        e.store.update { $0.fontSize = 22 }
        e.store.resetToDefault()
        e.settleWrite()
        #expect(e.bakBytes == nil && e.store.style == .default)
    }

    @Test func ensureFileExistsCreatesOnlyWhenMissing() {
        let e = started()
        #expect(e.bytes == nil)
        #expect(e.store.ensureFileExists())
        #expect(e.bytes == TickerStyle.default.normalizedJSON())
        e.put(##"{"fontSize": 12}"##)
        #expect(e.store.ensureFileExists() && e.bytes == Data(##"{"fontSize": 12}"##.utf8), "已存在不覆蓋")
    }
}

@Suite struct DispatchSourceWatcherTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    @Test func realWatcherFiresOnCreateAndOnRenameReplace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = DispatchSourceStyleWatcher()
        let c = Counter()
        #expect(w.start(directory: dir) { c.bump() })
        defer { w.stop() }
        let file = dir.appendingPathComponent("style.json")
        try Data("{}".utf8).write(to: file)
        #expect(waitUntil(timeout: 5) { c.value >= 1 }, "建立檔案")
        let after = c.value
        let tmp = dir.appendingPathComponent("style.json.sb-1")
        try Data(##"{"fontSize": 20}"##.utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
        #expect(waitUntil(timeout: 5) { c.value > after }, "改名取代式儲存（原檔 inode 換掉）仍有事件")
        Thread.sleep(forTimeInterval: 0.3)
        let afterReplace = c.value
        try FileManager.default.removeItem(at: file)
        #expect(waitUntil(timeout: 5) { c.value > afterReplace }, "刪除")
    }

    @Test func startOnMissingDirectoryReturnsFalse() {
        let w = DispatchSourceStyleWatcher()
        #expect(!w.start(directory: FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")) {})
    }

    @Test func storeWithRealWatcherReloadsEditInTempDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("realstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("style.json")
        let changes = ChangeLog()
        let store = StyleStore(fileURL: file, watcher: DispatchSourceStyleWatcher(), queue: DispatchQueue(label: "real-store-test"))
        store.onChange = { changes.add($0, $1) }
        store.start()
        defer { store.stopWatching() }
        try Data(##"{"fontSize": 21}"##.utf8).write(to: file)
        #expect(waitUntil(timeout: 5) { changes.count == 1 }, "真實 0.3 秒 debounce 後套用")
        #expect(store.style.fontSize == 21)
    }
}
