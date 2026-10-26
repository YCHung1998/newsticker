import Testing
import Foundation
@testable import FastBullTickerApp

/// 以 helper 的 `--list-sources` 決定可用來源（change source-switcher）。用假 helper 腳本，不連網。
@Suite struct AvailableSourcesTests {
    private func script(_ body: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("avail-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let u = d.appendingPathComponent("fake-helper.sh")
        try! Data("#!/bin/sh\n\(body)\n".utf8).write(to: u)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return u
    }

    @Test func parsesOneIdPerLineAndPassesTheFlag() {
        let h = script(#"[ "$1" = "--list-sources" ] || exit 9; printf 'fastbull\njin10\n\n  bloomberg \n'"#)
        #expect(AvailableSources.fetch(helper: h, timeout: 5) == ["fastbull", "jin10", "bloomberg"])
    }

    @Test func nonZeroExitIsNil() {
        #expect(AvailableSources.fetch(helper: script("echo fastbull; exit 2"), timeout: 5) == nil)
    }

    @Test func timeoutIsNilAndReturnsPromptly() {
        let t0 = Date()
        let r = AvailableSources.fetch(helper: script("sleep 30"), timeout: 0.5)
        #expect(r == nil)
        #expect(Date().timeIntervalSince(t0) < 5, "逾時要真的結束子行程，不能等它跑完")
    }

    @Test func missingExecutableIsNil() {
        #expect(AvailableSources.fetch(helper: URL(fileURLWithPath: "/nonexistent/ticker-connect"), timeout: 1) == nil)
    }

    @Test func emptyOutputIsNilNotAnEmptySet() {
        #expect(AvailableSources.fetch(helper: script("true"), timeout: 5) == nil)
    }

    @Test func invalidLinesAreDropped() {
        let h = script(#"printf 'fastbull\nBAD ID\njin10\n'"#)
        #expect(AvailableSources.fetch(helper: h, timeout: 5) == ["fastbull", "jin10"])
    }

    @Test func fallbackIsFastbullOnly() {
        #expect(AvailableSources.fallback == ["fastbull"])
    }
}
