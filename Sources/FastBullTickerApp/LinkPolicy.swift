import Foundation

/// 通過 `LinkPolicy` 驗證的 URL。唯一的建構途徑是 `LinkPolicy.openableURL(from:)`，
/// 因此「未驗證的 URL 被開啟」在型別層即無法通過編譯。
public struct OpenableURL: Equatable, Sendable {
    public let url: URL
    fileprivate init(_ url: URL) { self.url = url }
}

/// 協定層 `url` 規則之後的第二道防線：只允許 http／https、必須有 host、不得含 userinfo、長度 ≤ 2048 位元組、
/// 只含可見 ASCII（無空白與控制字元）、且 `URL` 解析成功。
public enum LinkPolicy {
    public static let maxBytes = 2048

    public static func openableURL(from string: String) -> OpenableURL? {
        let bytes = Array(string.utf8)
        guard !bytes.isEmpty, bytes.count <= maxBytes, bytes.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
        guard let url = URL(string: string, encodingInvalidCharacters: false),
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil
        else { return nil }
        return OpenableURL(url)
    }
}

/// 開啟連結的抽象（單一方法）。正式實作（`NSWorkspace`）只存在於 `Workspace*Opener.swift`，由 `AppDelegate` 組裝；
/// 自動測試只能使用假 opener。
@MainActor
public protocol URLOpener: AnyObject {
    /// 回傳是否成功開啟。
    func open(_ url: OpenableURL) -> Bool
}

public enum LinkOpenResult: Equatable, Sendable {
    case opened
    case openerFailed
    case blockedByPolicy
    case noURL
}

/// 點擊迴紋針的動作：先過 `LinkPolicy`，通過才呼叫 opener，恰一次、失敗不重試。
public enum LinkOpening {
    @MainActor
    public static func open(_ urlString: String?, using opener: URLOpener) -> LinkOpenResult {
        guard let urlString else { return .noURL }
        guard let openable = LinkPolicy.openableURL(from: urlString) else { return .blockedByPolicy }
        return opener.open(openable) ? .opened : .openerFailed
    }
}
