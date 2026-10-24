import Testing
import Foundation
@testable import FastBullTickerCore

/// 以 `protocol/fixtures/manifest.json` 為唯一預期來源（唯讀、不複製）。
struct ManifestSample {
    var name: String
    var expectAccept: Bool
    var reason: String?
    var bytes: [UInt8]
}

struct ContractError: Error, CustomStringConvertible { var description: String }

enum Manifest {
    static func load(protocolDir: URL) throws -> (maxLineBytes: Int, reasons: [String], samples: [ManifestSample], listedFiles: Set<String>) {
        let data = try Data(contentsOf: protocolDir.appendingPathComponent("fixtures/manifest.json"))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let maxBytes = try #require(root["max_line_bytes"] as? Int)
        let reasons = try #require(root["reasons"] as? [String])
        let raw = try #require(root["samples"] as? [[String: Any]])
        var out: [ManifestSample] = []
        var listed = Set<String>()
        for s in raw {
            let name = try #require(s["name"] as? String)
            let expect = try #require(s["expect"] as? String)
            var bytes: [UInt8]
            if let file = s["file"] as? String {
                listed.insert(file)
                // 缺檔必須丟出錯誤（測試失敗），不得略過。
                let d = try Data(contentsOf: protocolDir.appendingPathComponent("fixtures/" + file))
                guard d.last == 0x0A, d.filter({ $0 == 0x0A }).count == 1 else { throw ContractError(description: "\(file) 必須恰為一行") }
                bytes = Array(d.dropLast())
            } else if let gen = s["generate"] as? [String: Any] {
                bytes = try generate(gen, maxBytes: maxBytes)
            } else {
                throw ContractError(description: "樣本 \(name) 既無 file 也無 generate")
            }
            out.append(ManifestSample(name: name, expectAccept: expect == "accept", reason: s["reason"] as? String, bytes: bytes))
        }
        return (maxBytes, reasons, out, listed)
    }

    /// 與 protocol/refcheck.py `generate_line` 相同：合法 items 訊息，ASCII text 補到恰好 total 位元組。
    static func generate(_ spec: [String: Any], maxBytes: Int) throws -> [UInt8] {
        guard spec["kind"] as? String == "padded_items" else { throw ContractError(description: "未知 generate.kind \(spec)") }
        let total: Int
        switch spec["total_bytes"] as? String {
        case "limit": total = maxBytes
        case "limit+1": total = maxBytes + 1
        default: throw ContractError(description: "未知 total_bytes \(spec)")
        }
        func enc(_ pad: Int) -> [UInt8] {
            Array((#"{"v":1,"type":"items","items":[{"source":"fastbull","id":"1","published_at_ms":1761292800000,"text":""#
                + String(repeating: "a", count: pad) + #""}]}"#).utf8)
        }
        let pad = total - enc(0).count
        let out = enc(pad)
        guard out.count == total else { throw ContractError(description: "產生長度 \(out.count) != \(total)") }
        return out
    }
}

@Suite struct ContractFixturesTests {
    func protocolDir() throws -> URL {
        let root = try #require(TestSupport.repoRoot(), "找不到 protocol/fixtures/manifest.json")
        return root.appendingPathComponent("protocol")
    }

    @Test func everySampleMatchesManifest() throws {
        let m = try Manifest.load(protocolDir: try protocolDir())
        #expect(m.maxLineBytes == ProtocolRules.maxLineBytes)
        #expect(Set(m.reasons) == Set(DecodeErrorReason.allCases.map(\.rawValue)))
        #expect(m.samples.count >= 40, "manifest 樣本數異常少：\(m.samples.count)")
        for s in m.samples {
            let r = decodeLine(s.bytes)
            if s.expectAccept {
                if case .failure(let e) = r { Issue.record("\(s.name): 預期 accept，實際 reject(\(e.reason.rawValue))") }
            } else {
                switch r {
                case .success: Issue.record("\(s.name): 預期 reject(\(s.reason ?? "?"))，實際 accept")
                case .failure(let e): #expect(e.reason.rawValue == s.reason, "\(s.name): 原因 \(e.reason.rawValue) != \(s.reason ?? "nil")")
                }
            }
        }
    }

    @Test func generatedBoundarySamplesPresentAndCorrect() throws {
        let m = try Manifest.load(protocolDir: try protocolDir())
        let atLimit = try #require(m.samples.first { $0.name == "generated-at-limit" })
        let over = try #require(m.samples.first { $0.name == "generated-over-limit" })
        #expect(atLimit.bytes.count == 1_048_576 && over.bytes.count == 1_048_577)
        #expect(atLimit.expectAccept && !over.expectAccept)
    }

    @Test func manifestAndDirectoryAreOneToOne() throws {
        let dir = try protocolDir()
        let m = try Manifest.load(protocolDir: dir)
        var onDisk = Set<String>()
        for sub in ["valid", "invalid"] {
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("fixtures/" + sub).path)
            for f in files where f.hasSuffix(".jsonl") { onDisk.insert("\(sub)/\(f)") }
        }
        #expect(onDisk == m.listedFiles, "manifest 與目錄不一致：只在目錄 \(onDisk.subtracting(m.listedFiles).sorted())；只在 manifest \(m.listedFiles.subtracting(onDisk).sorted())")
    }

    @Test func missingFixtureFileFailsLoudly() throws {
        // 建立一份指向不存在檔案的 manifest 副本（暫存目錄），載入必須丟出錯誤而非略過。
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("fixtures"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let json = #"{"manifest_version":1,"max_line_bytes":1048576,"reasons":["schema"],"samples":[{"name":"ghost","file":"valid/ghost.jsonl","expect":"accept","covers":[]}]}"#
        try json.write(to: tmp.appendingPathComponent("fixtures/manifest.json"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { _ = try Manifest.load(protocolDir: tmp) }
    }
}
