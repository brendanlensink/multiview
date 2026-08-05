import CoreMedia
import MultipeerConnectivity
import SwiftUI

@MainActor @Observable
final class PeerVideoManager {
    private let logger = AppLogger.make(category: "PeerVideo")

    private var decoders: [MCPeerID: VideoDecoder] = [:]
    private(set) var displayLayers: [MCPeerID: SampleBufferDisplayLayer] = [:]

    func handleFrame(from peer: MCPeerID, packet: FramePacket) {
        let (decoder, layer) = decoderAndLayer(for: peer)
        decoder.decode(packet: packet)
    }

    func removePeer(_ peer: MCPeerID) {
        decoders[peer]?.invalidate()
        decoders.removeValue(forKey: peer)
        displayLayers.removeValue(forKey: peer)
    }

    func removeAllPeers() {
        for decoder in decoders.values {
            decoder.invalidate()
        }
        decoders.removeAll()
        displayLayers.removeAll()
    }

    func setRecordingCallback(for peer: MCPeerID, _ callback: @escaping @Sendable (CMSampleBuffer) -> Void) {
        decoders[peer]?.onRecordSampleBuffer = callback
    }

    func clearRecordingCallback(for peer: MCPeerID) {
        decoders[peer]?.onRecordSampleBuffer = nil
    }

    func clearRecordingCallbacks() {
        for decoder in decoders.values {
            decoder.onRecordSampleBuffer = nil
        }
    }

    #if targetEnvironment(simulator)
    func enqueueSimulatedFrame(_ sampleBuffer: CMSampleBuffer, from peer: MCPeerID) {
        let layer = ensureDisplayLayer(for: peer)
        layer.enqueue(sampleBuffer)
    }

    private func ensureDisplayLayer(for peer: MCPeerID) -> SampleBufferDisplayLayer {
        if let layer = displayLayers[peer] { return layer }
        let layer = SampleBufferDisplayLayer()
        displayLayers[peer] = layer
        logger.info("Created display layer for simulated peer \(peer.displayName)")
        return layer
    }
    #endif

    // MARK: - Private

    private func decoderAndLayer(for peer: MCPeerID) -> (VideoDecoder, SampleBufferDisplayLayer) {
        if let decoder = decoders[peer], let layer = displayLayers[peer] {
            return (decoder, layer)
        }

        let layer = SampleBufferDisplayLayer()
        let decoder = VideoDecoder()
        decoder.onSampleBuffer = { [weak layer] sampleBuffer in
            layer?.enqueue(sampleBuffer)
        }
        decoder.onFormatChanged = { [weak layer] in
            layer?.flush()
        }

        decoders[peer] = decoder
        displayLayers[peer] = layer
        logger.info("Created decoder and display layer for \(peer.displayName)")
        return (decoder, layer)
    }
}
