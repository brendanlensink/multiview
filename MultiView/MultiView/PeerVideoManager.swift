import MultipeerConnectivity
import os
import SwiftUI

@MainActor @Observable
final class PeerVideoManager {
    private let logger = Logger(subsystem: "com.multiview", category: "PeerVideo")

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

        decoders[peer] = decoder
        displayLayers[peer] = layer
        logger.info("Created decoder and display layer for \(peer.displayName)")
        return (decoder, layer)
    }
}
