import Foundation

public struct ArgError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}

/// 嚴格的命令列解析：未知參數、缺值、非法選項一律拋錯（程式以 exit 2 結束）。
public struct Args {
    public private(set) var values: [String: String] = [:]
    public private(set) var flags: Set<String> = []

    public init(argv: [String] = Array(CommandLine.arguments.dropFirst()),
                valueKeys: Set<String>, flagKeys: Set<String>) throws {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            guard a.hasPrefix("--") else { throw ArgError("unexpected argument: \(a)") }
            let key = String(a.dropFirst(2))
            if flagKeys.contains(key) {
                flags.insert(key); i += 1
            } else if valueKeys.contains(key) {
                guard i + 1 < argv.count else { throw ArgError("missing value for --\(key)") }
                values[key] = argv[i + 1]; i += 2
            } else {
                throw ArgError("unknown option: --\(key)")
            }
        }
    }

    public func has(_ flag: String) -> Bool { flags.contains(flag) }
    public func string(_ k: String) -> String? { values[k] }

    public func choice(_ k: String, _ def: String, allowed: [String]) throws -> String {
        let v = values[k] ?? def
        guard allowed.contains(v) else { throw ArgError("--\(k) must be one of \(allowed.joined(separator: "|")), got '\(v)'") }
        return v
    }
    public func onOff(_ k: String, _ def: Bool) throws -> Bool {
        let v = try choice(k, def ? "on" : "off", allowed: ["on", "off"])
        return v == "on"
    }
    public func double(_ k: String, _ def: Double) throws -> Double {
        guard let s = values[k] else { return def }
        guard let d = Double(s), d.isFinite else { throw ArgError("--\(k) must be a number, got '\(s)'") }
        return d
    }
}

public func failUsage(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}
