import Foundation
@testable import FastBullTickerCore

final class FakeClock { var t: Double = 0 }

extension SchedulerConfig {
    /// 測試用：speed 100、gap 20、視窗 200；每則訊息顯示字串 13 字元 → 寬 130（flatMeasure）。
    static var test: SchedulerConfig {
        var c = SchedulerConfig()
        c.speed = 100; c.gap = 20; c.viewportWidth = 200; c.maxItemWidth = 600
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
}

func makeScheduler(_ clock: FakeClock, config: SchedulerConfig = .test) -> TickerScheduler {
    TickerScheduler(config: config, clock: { clock.t }, measurer: flatMeasure)
}

/// n 越大越新；text 固定 4 字元 → 顯示字串 "HH:mm:ss tNNN" 13 字元 → 寬 130。
func it(_ n: Int, source: String = "fastbull") -> Item {
    Item(source: source, id: "\(n)", publishedAtMs: 1_000_000 + Int64(n) * 1000, text: String(format: "t%03d", n % 1000))
}
/// snapshot：新到舊。
func snap(_ ns: [Int]) -> Message { .snapshot(ns.sorted(by: >).map { it($0) }) }
/// items：舊到新。
func live(_ ns: [Int]) -> Message { .items(ns.sorted().map { it($0) }) }
let itemWidth = 130.0

extension TickerScheduler {
    /// 每步前進 dt 秒並 tick，累積所有新排入的訊息。
    mutating func run(_ clock: FakeClock, seconds: Double, step: Double = 0.1) -> [PlacedItem] {
        var out: [PlacedItem] = []
        let end = clock.t + seconds
        while clock.t < end - 1e-9 {
            clock.t += step
            out += tick()
        }
        return out
    }
}

/// 帶 `url` 的版本（連結欄位測試用）。
func itu(_ n: Int, source: String = "fastbull") -> Item {
    var i = it(n, source: source)
    i.url = "https://example.test/n/\(n)"
    return i
}

extension TickerScheduler {
    /// 以最多 1 秒的步長 tick 到時刻 t（避免一次大跳躍使尾端離開視窗而改排到右緣）。
    mutating func tickTo(_ clock: FakeClock, _ t: Double) {
        while clock.t + 1 < t { clock.t += 1; _ = tick() }
        clock.t = t; _ = tick()
    }
}
