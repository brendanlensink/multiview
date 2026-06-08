import MultipeerConnectivity
import VideoToolbox
import os
import SwiftUI

@MainActor @Observable
final class PeerVideoManager {
    private let logger = Logger(subsystem: "com.multiview", category: "PeerVideo")

    private var decoders: [MCPeerID: VideoDecoder] = [:]
    private(set) var latestFrames: [MCPeerID: CGImage] = [:]

    func handleFrame(from peer: MCPeerID, packet: FramePacket) {
        let decoder = decoders[peer] ?? createDecoder(for: peer)

        decoder.decode(packet: packet)
    }

    func removePeer(_ peer: MCPeerID) {
        decoders[peer]?.invalidate()
        decoders.removeValue(forKey: peer)
        latestFrames.removeValue(forKey: peer)
    }

    func removeAllPeers() {
        for decoder in decoders.values {
            decoder.invalidate()
        }
        decoders.removeAll()
        latestFrames.removeAll()
    }

    // MARK: - Private

    private func createDecoder(for peer: MCPeerID) -> VideoDecoder {
        let decoder = VideoDecoder()
        decoder.onDecodedFrame = { [weak self] pixelBuffer in
            guard let cgImage = Self.createCGImage(from: pixelBuffer) else { return }
            Task { @MainActor [weak self] in
                self?.latestFrames[peer] = cgImage
            }
        }
        decoders[peer] = decoder
        logger.info("Created decoder for \(peer.displayName)")
        return decoder
    }

    private static func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
}
