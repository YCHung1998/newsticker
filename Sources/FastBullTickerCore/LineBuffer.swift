/// LineBuffer 輸出的事件。
public enum LineEvent: Equatable, Sendable {
    /// 完整一行（不含 0x0A）。可能是空行。
    case line([UInt8])
    /// 超長行已被丟棄；`discardedBytes` 為整行位元組數（不含 0x0A），於該行的 0x0A 到達時輸出一次。
    case oversize(discardedBytes: Int)
}

/// 位元組層切行：以 0x0A 切，保留半行，單行上限，超長行只計數不累積，壞行不影響後續。
public struct LineBuffer: Sendable {
    public let maxLineBytes: Int
    private var buffer: [UInt8] = []
    private var discardedCount = 0       // 僅在 discarding 時有意義：目前已見的超長行位元組數
    private var discarding = false

    public init(maxLineBytes: Int = ProtocolRules.maxLineBytes) {
        precondition(maxLineBytes > 0)
        self.maxLineBytes = maxLineBytes
    }

    /// 目前保留的半行位元組數（上界為 `maxLineBytes`）。
    public var bufferedCount: Int { buffer.count }
    public var isDiscarding: Bool { discarding }

    public mutating func feed(_ chunk: [UInt8]) -> [LineEvent] {
        var events: [LineEvent] = []
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let nl = chunk[start...].firstIndex(of: 0x0A)
            let end = nl ?? chunk.endIndex
            let segment = chunk[start..<end]
            if discarding {
                discardedCount += segment.count
            } else if buffer.count + segment.count > maxLineBytes {
                // 超過上限：丟掉已緩衝的內容，只計數。
                discarding = true
                discardedCount = buffer.count + segment.count
                buffer.removeAll(keepingCapacity: false)
            } else {
                buffer.append(contentsOf: segment)
            }
            if let nl {
                if discarding {
                    events.append(.oversize(discardedBytes: discardedCount))
                    discarding = false
                    discardedCount = 0
                } else {
                    events.append(.line(buffer))
                    buffer.removeAll(keepingCapacity: true)
                }
                start = nl + 1
            } else {
                start = chunk.endIndex
            }
        }
        return events
    }

    /// 串流結束：未以 0x0A 結尾的殘留半行不輸出，回傳被丟棄的位元組數並重置。
    public mutating func finish() -> Int {
        let n = discarding ? discardedCount : buffer.count
        buffer.removeAll(); discarding = false; discardedCount = 0
        return n
    }
}
