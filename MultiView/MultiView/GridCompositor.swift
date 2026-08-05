import AVFoundation
import CoreGraphics

struct GridCompositor {
    private static let logger = AppLogger.make(category: "GridCompositor")

    static let outputSize = CGSize(width: 1920, height: 1080)

    enum CompositorError: LocalizedError {
        case noStreams
        case noVideoTrack(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noStreams:
                "No video streams found in the recording session."
            case .noVideoTrack(let label):
                "No video track found in stream '\(label)'."
            case .exportFailed(let reason):
                "Export failed: \(reason)"
            }
        }
    }

    static func composite(_ session: RecordingSession, onProgress: (@Sendable (Float) -> Void)? = nil) async throws -> URL {
        let streams = session.streams
        guard !streams.isEmpty else { throw CompositorError.noStreams }

        let assets = streams.map { stream in
            AVURLAsset(url: RecordingStore.fileURL(for: stream, in: session))
        }

        let composition = AVMutableComposition()
        var layerConfigs: [AVVideoCompositionLayerInstruction.Configuration] = []
        var maxDuration: CMTime = .zero

        for (index, asset) in assets.enumerated() {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first else {
                logger.warning("No video track in stream '\(streams[index].label)', skipping")
                continue
            }

            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            let duration = try await asset.load(.duration)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceVideoTrack,
                at: .zero
            )

            if duration > maxDuration {
                maxDuration = duration
            }

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let videoSize = CGSize(
                width: abs(transformedSize.width),
                height: abs(transformedSize.height)
            )

            let cellRect = gridRect(for: index, of: assets.count, in: outputSize)
            let transform = fitTransform(
                videoSize: videoSize,
                preferredTransform: preferredTransform,
                into: cellRect
            )

            var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionTrack)
            layerConfig.setTransform(transform, at: .zero)
            layerConfigs.append(layerConfig)
        }

        guard !layerConfigs.isEmpty else { throw CompositorError.noStreams }

        let audioStream = streams.first { $0.hasAudio }
        if let audioStream {
            let audioAsset = AVURLAsset(url: RecordingStore.fileURL(for: audioStream, in: session))
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let duration = try await audioAsset.load(.duration)
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceAudioTrack,
                    at: .zero
                )
            }
        }

        let layerInstructions = layerConfigs.map {
            AVVideoCompositionLayerInstruction(configuration: $0)
        }

        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: maxDuration)
        instructionConfig.layerInstructions = layerInstructions
        instructionConfig.backgroundColor = CGColor(gray: 0, alpha: 1)

        let videoComposition = AVVideoComposition(configuration: .init(
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [AVVideoCompositionInstruction(configuration: instructionConfig)],
            renderSize: outputSize
        ))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composite-\(session.id).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CompositorError.exportFailed("Could not create export session")
        }

        exportSession.videoComposition = videoComposition

        if let onProgress {
            nonisolated(unsafe) let session = exportSession
            let progressTask = Task.detached {
                while !Task.isCancelled {
                    onProgress(session.progress)
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            try await exportSession.export(to: outputURL, as: .mov)
            progressTask.cancel()
            onProgress(1.0)
        } else {
            try await exportSession.export(to: outputURL, as: .mov)
        }

        logger.info("Grid composite exported to \(outputURL.lastPathComponent)")
        return outputURL
    }

    // MARK: - Grid Layout

    private static func gridRect(for index: Int, of count: Int, in size: CGSize) -> CGRect {
        switch count {
        case 1:
            return CGRect(origin: .zero, size: size)
        case 2:
            let halfWidth = size.width / 2
            return CGRect(
                x: CGFloat(index) * halfWidth,
                y: 0,
                width: halfWidth,
                height: size.height
            )
        default:
            let cellWidth = size.width / 2
            let cellHeight = size.height / 2
            let col = index % 2
            let row = index / 2
            return CGRect(
                x: CGFloat(col) * cellWidth,
                y: CGFloat(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
        }
    }

    private static func fitTransform(
        videoSize: CGSize,
        preferredTransform: CGAffineTransform,
        into rect: CGRect
    ) -> CGAffineTransform {
        let scaleX = rect.width / videoSize.width
        let scaleY = rect.height / videoSize.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = videoSize.width * scale
        let scaledHeight = videoSize.height * scale
        let offsetX = rect.origin.x + (rect.width - scaledWidth) / 2
        let offsetY = rect.origin.y + (rect.height - scaledHeight) / 2

        var transform = preferredTransform

        let tx = preferredTransform.tx
        let ty = preferredTransform.ty
        transform.tx = 0
        transform.ty = 0

        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        transform.tx += tx * scale + offsetX
        transform.ty += ty * scale + offsetY

        return transform
    }
}
