import Foundation

public enum SysInfo {
    /// `sw_vers` 的輸出（ProductName/ProductVersion/BuildVersion），不需任何權限。
    public static func swVers() -> [(String, String)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
        let pipe = Pipe()
        p.standardOutput = pipe
        do { try p.run() } catch { return [("sw_vers", "unavailable")] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var res: [(String, String)] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { res.append(("sw_vers." + parts[0], parts[1])) }
        }
        return res
    }
}
