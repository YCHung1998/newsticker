import Testing
import Foundation
@testable import FastBullTickerApp

// task 7.1：opener 只收 OpenableURL（型別層）。正式實作 WorkspaceURLOpener 在自動測試中從不呼叫。
@MainActor
@Suite struct NavigationLinkOpenerTests {
    @Test func openerProtocolOnlyAcceptsOpenableURL() {
        let fake = RecordingURLOpener()
        let f: (OpenableURL) -> Bool = fake.open
        #expect(f(LinkPolicy.openableURL(from: "https://example.com/demo/1")!))
        #expect(fake.opened.map(\.absoluteString) == ["https://example.com/demo/1"])
    }

    @Test func workspaceOpenerConformsButIsNeverInvokedHere() {
        // 只做型別層檢查：存在、符合 URLOpener；不呼叫 open，所以不會開啟任何瀏覽器。
        let make: () -> URLOpener = { WorkspaceURLOpener(onFailure: { _ in }) }
        _ = make
        #expect(WorkspaceURLOpener.opensWithActivation == true, "預設讓瀏覽器成為前景（是瀏覽器，不是本 App）")
    }
}
