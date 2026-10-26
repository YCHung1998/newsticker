import Testing
import Foundation
@testable import FastBullTickerApp

/// `sources.json`（change source-switcher）：格式、預設、容錯、記住選擇。
@Suite struct SourceRegistryTests {
    private func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("srcreg-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("sources.json")
    }
    private func write(_ s: String, to u: URL) { try! Data(s.utf8).write(to: u) }
    private func parse(_ s: String) -> SourceRegistry.ParseResult { SourceRegistry.parse(Data(s.utf8)) }

    // MARK: 格式

    @Test func validFileKeepsOrderNamesAndLabels() {
        let r = parse(#"{"version":1,"selected":"jin10","sources":[{"id":"jin10","name":"金十數據","label":"金十"},{"id":"fastbull","name":"FastBull 快訊"}]}"#)
        guard case .ok(let reg, let warnings) = r else { Issue.record("rejected"); return }
        #expect(reg.selected == "jin10")
        #expect(reg.sources.map(\.id) == ["jin10", "fastbull"])
        #expect(reg.sources[0].label == "金十" && reg.sources[1].label == nil)
        #expect(warnings.isEmpty)
    }

    @Test func duplicateIdKeepsFirstWithWarning() {
        guard case .ok(let reg, let w) = parse(#"{"selected":"a1","sources":[{"id":"a1","name":"第一"},{"id":"a1","name":"第二"}]}"#) else { Issue.record(); return }
        #expect(reg.sources.count == 1 && reg.sources[0].name == "第一")
        #expect(w.contains { $0.contains("a1") })
    }

    @Test func badEntriesAreSkippedOthersLoad() {
        guard case .ok(let reg, let w) = parse(#"{"selected":"jin10","sources":[{"id":"Bad Id","name":"x"},{"id":"nonamé"},{"id":"jin10","name":"金十"},{"id":"x","name":"短 id"},{"id":"ok_1","name":"   "}]}"#) else { Issue.record(); return }
        #expect(reg.sources.map(\.id) == ["jin10"])
        #expect(w.count == 4)
    }

    @Test func nameAndLabelAreTrimmedAndLengthChecked() {
        guard case .ok(let reg, _) = parse(#"{"selected":"jin10","sources":[{"id":"jin10","name":"  金十  ","label":"  標籤  "},{"id":"toolong","name":"\#(String(repeating: "字", count: 25))"},{"id":"lbl_long","name":"ok","label":"\#(String(repeating: "字", count: 17))"}]}"#) else { Issue.record(); return }
        #expect(reg.sources[0].name == "金十" && reg.sources[0].label == "標籤")
        #expect(reg.sources.map(\.id) == ["jin10", "lbl_long"], "name 過長整筆略過")
        #expect(reg.sources[1].label == nil, "label 不合法只丟 label，來源保留")
    }

    @Test func unknownKeysAreIgnoredWithWarning() {
        guard case .ok(let reg, let w) = parse(#"{"selected":"jin10","foo":1,"sources":[{"id":"jin10","name":"金十","bar":2}]}"#) else { Issue.record(); return }
        #expect(reg.sources.count == 1)
        #expect(w.count == 2)
    }

    @Test func notJSONOrNoValidSourcesIsInvalid() {
        for bad in ["{ oops", "[]", "42", #"{"sources":[]}"#, #"{"sources":[{"id":"BAD"}]}"#, #"{"selected":"x"}"#, ""] {
            if case .invalid = parse(bad) {} else { Issue.record("應為 invalid：\(bad)") }
        }
    }

    // MARK: 預設與自動建立

    @Test func defaultContentIsFastbullThenJin10() {
        let d = SourceRegistry.default
        #expect(d.selected == "fastbull")
        #expect(d.sources.map(\.id) == ["fastbull", "jin10"])
        #expect(d.sources[0].name == "FastBull 快訊" && d.sources[0].label == "即時財經快訊")
        #expect(d.sources[1].name == "金十數據" && d.sources[1].label == "金十數據")
    }

    @Test func missingFileIsCreatedWithDefaultsAndRoundTrips() throws {
        let u = tmp()
        let out = SourceRegistryStore(url: u).load()
        #expect(out.registry == .default && out.notice == nil)
        #expect(FileManager.default.fileExists(atPath: u.path))
        guard case .ok(let reg, _) = SourceRegistry.parse(try Data(contentsOf: u)) else { Issue.record(); return }
        #expect(reg == .default)
    }

    @Test func unwritableLocationFallsBackToMemoryDefault() {
        // 父路徑是一個「檔案」，無法在其下建立目錄或檔案。
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try! Data("x".utf8).write(to: blocker)
        let u = blocker.appendingPathComponent("sources.json")
        let out = SourceRegistryStore(url: u).load()
        #expect(out.registry == .default)
        #expect(out.writeError != nil)
        #expect(SourceRegistryStore(url: u).select("jin10") == false, "寫不進去要回報 false，不崩潰")
    }

    // MARK: 容錯

    @Test func corruptFileIsBackedUpAndReplacedWithDefaults() throws {
        let u = tmp()
        write("{ oops", to: u)
        let out = SourceRegistryStore(url: u).load()
        #expect(out.registry == .default)
        #expect(out.notice != nil)
        let bak = u.appendingPathExtension("bak")
        #expect(try String(contentsOf: bak, encoding: .utf8) == "{ oops")
        guard case .ok = SourceRegistry.parse(try Data(contentsOf: u)) else { Issue.record("原檔應被預設取代"); return }
    }

    // MARK: 記住選擇

    @Test func selectPersistsAndKeepsOrderNamesAndLabels() throws {
        let u = tmp()
        write(#"{"version":1,"selected":"fastbull","sources":[{"id":"jin10","name":"金十","label":"J"},{"id":"fastbull","name":"FB"}]}"#, to: u)
        let store = SourceRegistryStore(url: u)
        #expect(store.select("jin10"))
        let out = store.load()
        #expect(out.registry.selected == "jin10")
        #expect(out.registry.sources.map(\.id) == ["jin10", "fastbull"])
        #expect(out.registry.sources[0].label == "J" && out.registry.sources[1].name == "FB")
    }

    @Test func effectiveSelectionFallsBackToFastbullWithoutTouchingFile() throws {
        let u = tmp()
        write(#"{"selected":"nope","sources":[{"id":"fastbull","name":"FB"},{"id":"jin10","name":"J"}]}"#, to: u)
        let before = try Data(contentsOf: u)
        let reg = SourceRegistryStore(url: u).load().registry
        #expect(reg.effectiveSelection(available: ["fastbull", "jin10"]) == "fastbull")
        #expect(try Data(contentsOf: u) == before)
        // 指向的來源存在但 helper 沒有該連接器 → 也退回 fastbull
        let reg2 = SourceRegistry(selected: "jin10", sources: reg.sources)
        #expect(reg2.effectiveSelection(available: ["fastbull"]) == "fastbull")
        #expect(reg2.effectiveSelection(available: ["fastbull", "jin10"]) == "jin10")
    }
}
