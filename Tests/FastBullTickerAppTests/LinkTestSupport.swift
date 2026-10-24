import Foundation
@testable import FastBullTickerApp

/// 記錄用假 opener：自動測試只能用它，絕不碰 `NSWorkspace`。
@MainActor
final class RecordingURLOpener: URLOpener {
    private(set) var opened: [URL] = []
    var result = true
    func open(_ url: OpenableURL) -> Bool {
        opened.append(url.url)
        return result
    }
}
