import Foundation

final class FrameSender: @unchecked Sendable {
    private let logger = AppLogger.make(category: "FrameSender")

    private let send: @Sendable (FramePacket, SendMode) -> Void
    private let queue = DispatchQueue(label: "com.multiview.frame-sender")
    private var pendingBytes: Int = 0
    private var totalFrames: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var lastStatsLog = ContinuousClock.now

    private static let maxPendingBytes = 2 * 1024 * 1024 // 2 MB
    private static let statsInterval: Duration = .seconds(10)

    enum SendMode {
        case reliable
        case unreliable
    }

    init(send: @escaping @Sendable (FramePacket, SendMode) -> Void) {
        self.send = send
    }

    func enqueue(_ packet: FramePacket) {
        queue.async { [self] in
            totalFrames += 1

            if !packet.isKeyFrame && pendingBytes > Self.maxPendingBytes {
                droppedFrames += 1
                logStatsIfNeeded()
                return
            }

            let size = packet.payload.count + (packet.parameterSets?.count ?? 0)
            pendingBytes += size

            let mode: SendMode = packet.isKeyFrame ? .reliable : .unreliable
            send(packet, mode)

            pendingBytes -= size
            logStatsIfNeeded()
        }
    }

    private func logStatsIfNeeded() {
        let now = ContinuousClock.now
        guard now - lastStatsLog >= Self.statsInterval else { return }
        lastStatsLog = now

        let dropRate = totalFrames > 0 ? Double(droppedFrames) / Double(totalFrames) * 100 : 0
        logger.info("Stats — sent: \(self.totalFrames - self.droppedFrames), dropped: \(self.droppedFrames) (\(String(format: "%.1f", dropRate))%), pending: \(self.pendingBytes) bytes")

        totalFrames = 0
        droppedFrames = 0
    }
}
