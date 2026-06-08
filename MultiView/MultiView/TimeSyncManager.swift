import Foundation
import MultipeerConnectivity
import os

struct SyncPing {
    static let messageType: UInt8 = 0x02

    let sequence: UInt32
    let senderTime: UInt64

    func serialized() -> Data {
        var data = Data(capacity: 13)
        data.append(Self.messageType)
        var seq = sequence.bigEndian
        data.append(Data(bytes: &seq, count: 4))
        var t = senderTime.bigEndian
        data.append(Data(bytes: &t, count: 8))
        return data
    }

    init(sequence: UInt32, senderTime: UInt64) {
        self.sequence = sequence
        self.senderTime = senderTime
    }

    init?(data: Data) {
        guard data.count == 12 else { return nil }
        self.sequence = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.senderTime = data.subdata(in: 4..<12).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }
}

struct SyncPong {
    static let messageType: UInt8 = 0x03

    let sequence: UInt32
    let originTime: UInt64
    let receiveTime: UInt64
    let transmitTime: UInt64

    func serialized() -> Data {
        var data = Data(capacity: 29)
        data.append(Self.messageType)
        var seq = sequence.bigEndian
        data.append(Data(bytes: &seq, count: 4))
        var t1 = originTime.bigEndian
        data.append(Data(bytes: &t1, count: 8))
        var t2 = receiveTime.bigEndian
        data.append(Data(bytes: &t2, count: 8))
        var t3 = transmitTime.bigEndian
        data.append(Data(bytes: &t3, count: 8))
        return data
    }

    init(sequence: UInt32, originTime: UInt64, receiveTime: UInt64, transmitTime: UInt64) {
        self.sequence = sequence
        self.originTime = originTime
        self.receiveTime = receiveTime
        self.transmitTime = transmitTime
    }

    init?(data: Data) {
        guard data.count == 28 else { return nil }
        self.sequence = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.originTime = data.subdata(in: 4..<12).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        self.receiveTime = data.subdata(in: 12..<20).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        self.transmitTime = data.subdata(in: 20..<28).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }
}

final class TimeSyncManager: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "TimeSync")

    private let queue = DispatchQueue(label: "com.multiview.time-sync")
    private var offsets: [MCPeerID: Int64] = [:]
    private var roundTripTimes: [MCPeerID: UInt64] = [:]
    private var nextSequence: UInt32 = 0
    private var pendingPings: [UInt32: (peer: MCPeerID, sendTime: UInt64)] = [:]
    private var refreshTimers: [MCPeerID: DispatchSourceTimer] = [:]

    private static let refreshInterval: TimeInterval = 30
    private static let sampleCount = 5

    private let sendData: @Sendable (Data, MCPeerID) -> Void

    init(sendData: @escaping @Sendable (Data, MCPeerID) -> Void) {
        self.sendData = sendData
    }

    // MARK: - Director Side

    func startSync(with peer: MCPeerID) {
        queue.async { [self] in
            sendPing(to: peer)
            startRefreshTimer(for: peer)
        }
    }

    func stopSync(with peer: MCPeerID) {
        queue.async { [self] in
            refreshTimers[peer]?.cancel()
            refreshTimers.removeValue(forKey: peer)
            offsets.removeValue(forKey: peer)
            roundTripTimes.removeValue(forKey: peer)
            pendingPings = pendingPings.filter { $0.value.peer != peer }
        }
    }

    func stopAll() {
        queue.async { [self] in
            for timer in refreshTimers.values { timer.cancel() }
            refreshTimers.removeAll()
            offsets.removeAll()
            roundTripTimes.removeAll()
            pendingPings.removeAll()
        }
    }

    func handlePong(_ pong: SyncPong) {
        queue.async { [self] in
            let t4 = Self.currentTimestampNanos()

            guard let pending = pendingPings.removeValue(forKey: pong.sequence) else {
                logger.warning("Received pong for unknown sequence \(pong.sequence)")
                return
            }

            let t1 = pending.sendTime
            let t2 = pong.receiveTime
            let t3 = pong.transmitTime

            let rtt = (t4 - t1) - (t3 - t2)
            let offset = (Int64(bitPattern: t2) - Int64(bitPattern: t1) + Int64(bitPattern: t3) - Int64(bitPattern: t4)) / 2

            let peer = pending.peer
            if let existingOffset = offsets[peer] {
                // Exponential moving average for stability
                offsets[peer] = existingOffset + (offset - existingOffset) / 4
            } else {
                offsets[peer] = offset
            }
            roundTripTimes[peer] = rtt

            logger.info("Sync with \(peer.displayName): offset=\(self.offsets[peer]!)ns, RTT=\(rtt)ns (\(Double(rtt) / 1_000_000, format: .fixed(precision: 1))ms)")
        }
    }

    func offset(for peer: MCPeerID) -> Int64? {
        queue.sync { offsets[peer] }
    }

    func adjustedPresentationTime(_ pts: UInt64, from peer: MCPeerID) -> UInt64 {
        guard let offset = queue.sync(execute: { offsets[peer] }) else { return pts }
        // director_time = camera_time - offset
        return UInt64(bitPattern: Int64(bitPattern: pts) - offset)
    }

    // MARK: - Camera Side

    func handlePing(_ ping: SyncPing, from peer: MCPeerID) {
        let receiveTime = Self.currentTimestampNanos()
        let transmitTime = Self.currentTimestampNanos()
        let pong = SyncPong(
            sequence: ping.sequence,
            originTime: ping.senderTime,
            receiveTime: receiveTime,
            transmitTime: transmitTime
        )
        sendData(pong.serialized(), peer)
    }

    // MARK: - Private

    private func sendPing(to peer: MCPeerID) {
        let seq = nextSequence
        nextSequence += 1
        let now = Self.currentTimestampNanos()
        pendingPings[seq] = (peer: peer, sendTime: now)
        let ping = SyncPing(sequence: seq, senderTime: now)
        sendData(ping.serialized(), peer)
        logger.debug("Sent sync ping \(seq) to \(peer.displayName)")
    }

    private func startRefreshTimer(for peer: MCPeerID) {
        refreshTimers[peer]?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.sendPing(to: peer)
        }
        refreshTimers[peer] = timer
        timer.resume()
    }

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func currentTimestampNanos() -> UInt64 {
        let ticks = mach_absolute_time()
        return ticks * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    }
}
