import Foundation

/// Reassembles Encryption2 frames independently of notification boundaries.
/// Wire length is the payload-length byte plus the 13-byte framing overhead.
public struct BleFrameBuffer {
    private var pending: [UInt8] = []
    public init() { }
    public var pendingBytes: Int { pending.count }

    public mutating func clear() { pending.removeAll(keepingCapacity: false) }

    public mutating func accept(_ chunk: Data) -> [[UInt8]] {
        guard !chunk.isEmpty else { return [] }
        // A valid frame is at most 268 bytes. Bound malformed/noisy input too.
        if pending.count + chunk.count > 4096 { pending.removeAll(keepingCapacity: true) }
        pending.append(contentsOf: chunk.suffix(4096))
        var frames: [[UInt8]] = []
        var offset = 0
        while offset + 1 < pending.count {
            guard pending[offset] == 0x5A, pending[offset + 1] == 0xA5 else {
                offset += 1
                continue
            }
            guard pending.count - offset >= 3 else { break }
            let size = Int(pending[offset + 2]) + 13
            guard pending.count - offset >= size else { break }
            frames.append(Array(pending[offset..<(offset + size)]))
            offset += size
        }
        if offset > 0 { pending.removeFirst(offset) }
        if pending.count == 1, pending[0] != 0x5A { pending.removeAll(keepingCapacity: true) }
        return frames
    }
}
