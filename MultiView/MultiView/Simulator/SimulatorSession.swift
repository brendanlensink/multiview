#if targetEnvironment(simulator)
import CoreMedia
import MultipeerConnectivity
import os
import QuartzCore

@MainActor
final class SimulatorSession {
    private let logger = Logger(subsystem: "com.multiview", category: "Simulator")

    private let peerVideoManager: PeerVideoManager
    private let localDisplayLayer: SampleBufferDisplayLayer
    private let connectivity: ConnectivityManager
    private var displayLink: CADisplayLink?
    private var frameCount: Int64 = 0

    let simulatedPeers: [MCPeerID] = [
        MCPeerID(displayName: "Camera 1"),
        MCPeerID(displayName: "Camera 2 (landscape)"),
    ]

    private var localPixelBuffer: CVPixelBuffer?
    private var peerPixelBuffers: [MCPeerID: CVPixelBuffer] = [:]

    init(
        peerVideoManager: PeerVideoManager,
        localDisplayLayer: SampleBufferDisplayLayer,
        connectivity: ConnectivityManager
    ) {
        self.peerVideoManager = peerVideoManager
        self.localDisplayLayer = localDisplayLayer
        self.connectivity = connectivity
    }

    func start() {
        logger.info("Starting simulator session with \(self.simulatedPeers.count) fake peers")

        localPixelBuffer = TestPatternGenerator.createPixelBuffer(label: "Director", color: .blue)

        let colors: [TestPatternColor] = [.green, .orange, .purple]
        for (i, peer) in simulatedPeers.enumerated() {
            let isLandscape = peer.displayName.contains("landscape")
            peerPixelBuffers[peer] = TestPatternGenerator.createPixelBuffer(
                label: peer.displayName,
                color: colors[i % colors.count],
                landscape: isLandscape
            )
        }

        connectivity.simulateConnectedPeers(simulatedPeers)

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link

        logger.info("Simulator session started")
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        localPixelBuffer = nil
        peerPixelBuffers.removeAll()
        logger.info("Simulator session stopped")
    }

    @objc private func tick() {
        let timestamp = CMTime(value: frameCount, timescale: 30)
        frameCount += 1

        if let buffer = localPixelBuffer,
           let sample = TestPatternGenerator.createSampleBuffer(from: buffer, timestamp: timestamp) {
            localDisplayLayer.enqueue(sample)
        }

        for (peer, buffer) in peerPixelBuffers {
            if let sample = TestPatternGenerator.createSampleBuffer(from: buffer, timestamp: timestamp) {
                peerVideoManager.enqueueSimulatedFrame(sample, from: peer)
            }
        }
    }
}
#endif
