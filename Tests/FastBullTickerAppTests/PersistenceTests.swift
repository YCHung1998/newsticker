import Testing
import Foundation
import CoreGraphics
@testable import FastBullTickerApp

// task 3.1：Persistence。執行：swift test --filter Persistence

private let primary = ScreenInfo(uuid: "PRIMARY", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
private let external = ScreenInfo(uuid: "EXTERNAL", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                  visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
private let size = CGSize(width: 620, height: 42)

private func freshDefaults() -> (UserDefaults, String) {
    let name = "FastBullTickerTests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

@Suite struct PersistenceClampTests {
    @Test func clampPullsFullyOffscreenFrameBackInside() {
        let off = CGRect(x: 5000, y: -3000, width: 620, height: 42)
        let c = PlacementMath.clamp(off, into: primary.visibleFrame)
        #expect(primary.visibleFrame.contains(c))
        #expect(c.size == off.size)
    }

    @Test func clampLeavesAlreadyVisibleFrameUntouched() {
        let f = CGRect(x: 100, y: 100, width: 620, height: 42)
        #expect(PlacementMath.clamp(f, into: primary.visibleFrame) == f)
    }

    @Test func missingScreenFallsBackToPrimaryAndIsVisible() throws {
        let saved = PanelPlacement(screenUUID: "UNPLUGGED", offsetX: 2500, offsetY: 400)   // 外接螢幕座標，已拔除
        let f = try #require(PlacementMath.restore(saved, size: size, screens: [primary]))
        #expect(primary.visibleFrame.contains(f))
    }

    @Test func offsetOutsideVisibleAreaIsClampedToPartiallyVisibleAtLeast() throws {
        let saved = PanelPlacement(screenUUID: "PRIMARY", offsetX: -9000, offsetY: 9000)
        let f = try #require(PlacementMath.restore(saved, size: size, screens: [primary, external]))
        #expect(!f.intersection(primary.visibleFrame).isNull)
        #expect(f.intersection(primary.visibleFrame).width > 0)
    }

    @Test func savedExternalScreenIsRestoredOntoExternal() throws {
        let saved = PanelPlacement(screenUUID: "EXTERNAL", offsetX: 300, offsetY: 500)
        let f = try #require(PlacementMath.restore(saved, size: size, screens: [primary, external]))
        #expect(f.origin == CGPoint(x: 1740, y: 500))
    }

    @Test func noSavedPlacementCentersAtTopOfPrimary() throws {
        let f = try #require(PlacementMath.restore(nil, size: size, screens: [primary]))
        #expect(f.midX == primary.visibleFrame.midX)
        #expect(primary.visibleFrame.contains(f))
    }

    @Test func placementUsesScreenWithLargestOverlap() throws {
        let f = CGRect(x: 1600, y: 200, width: 620, height: 42)
        let p = try #require(PlacementMath.placement(for: f, screens: [primary, external]))
        #expect(p == PanelPlacement(screenUUID: "EXTERNAL", offsetX: 160, offsetY: 200))
    }

    @Test func reclampAfterScreenUnplugMovesPanelOntoPrimary() throws {
        let onExternal = CGRect(x: 2000, y: 300, width: 620, height: 42)
        let f = try #require(PlacementMath.reclamp(onExternal, screens: [primary]))
        #expect(primary.visibleFrame.contains(f))
    }

    @Test func noScreensYieldsNil() {
        #expect(PlacementMath.restore(nil, size: size, screens: []) == nil)
        #expect(PlacementMath.reclamp(.zero, screens: []) == nil)
    }
}

@Suite struct PersistenceStoreTests {
    @Test func roundTripPlacementAndAlpha() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let s = UserDefaultsStore(defaults: d)
        #expect(s.loadPlacement() == nil && s.loadAlpha() == nil)
        s.savePlacement(PanelPlacement(screenUUID: "U", offsetX: 120, offsetY: 40))
        s.saveAlpha(0.6)
        let s2 = UserDefaultsStore(defaults: d)     // 模擬重啟
        #expect(s2.loadPlacement() == PanelPlacement(screenUUID: "U", offsetX: 120, offsetY: 40))
        #expect(s2.loadAlpha() == 0.6)
    }

    @Test func storeSurfaceHasNoClickThroughField() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        let s = UserDefaultsStore(defaults: d)
        s.savePlacement(PanelPlacement(screenUUID: "U", offsetX: 1, offsetY: 2)); s.saveAlpha(0.5)
        let keys = d.persistentDomain(forName: name)?.keys.map { $0.lowercased() } ?? []
        #expect(!keys.isEmpty)
        #expect(!keys.contains { $0.contains("click") || $0.contains("through") })
    }

    @Test func shellConfigClampsAlphaToFloor() {
        let c = ShellConfig.provisional
        #expect(c.clampAlpha(0.0) == c.alphaRange.lowerBound)
        #expect(c.alphaRange.lowerBound > 0.2)
        #expect(c.clampAlpha(5) == 1.0)
    }
}

@Suite struct PersistenceDebounceTests {
    final class RecordingStore: PersistenceStore, @unchecked Sendable {
        var placements: [PanelPlacement] = []
        func loadPlacement() -> PanelPlacement? { placements.last }
        func savePlacement(_ p: PanelPlacement) { placements.append(p) }
        func loadAlpha() -> Double? { nil }
        func saveAlpha(_ a: Double) {}
    }

    @Test func fiftyMovesWithinOneHundredMillisecondsWriteOnceWithFinalPosition() {
        let clock = FakeClock()
        let store = RecordingStore()
        let queue = DispatchQueue(label: "test.persist")
        let saver = PlacementSaver(store: store, clock: clock, queue: queue, delay: 0.5, screens: { [primary] })
        for i in 0..<50 {
            saver.noteMoved(CGRect(x: 100 + Double(i), y: 200, width: 620, height: 42))
            clock.advance(by: 0.002)                    // 50 次共 100ms
        }
        #expect(store.placements.isEmpty)               // 尚未到期
        clock.advance(by: 0.45)                         // 距最後一次移動 0.45s < 0.5s：debounce 從「最後一次」起算
        #expect(store.placements.isEmpty)
        clock.advance(by: 0.1)
        #expect(store.placements.count == 1)
        #expect(store.placements.first == PanelPlacement(screenUUID: "PRIMARY", offsetX: 149, offsetY: 200))
        #expect(saver.writeCount == 1)
    }

    @Test func separatedMovesWriteSeparately() {
        let clock = FakeClock()
        let store = RecordingStore()
        let saver = PlacementSaver(store: store, clock: clock, queue: DispatchQueue(label: "test.persist2"), delay: 0.5, screens: { [primary] })
        saver.noteMoved(CGRect(x: 10, y: 10, width: 620, height: 42)); clock.advance(by: 1)
        saver.noteMoved(CGRect(x: 20, y: 10, width: 620, height: 42)); clock.advance(by: 1)
        #expect(store.placements.map(\.offsetX) == [10, 20])
    }
}
