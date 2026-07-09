import AVFoundation
import os

final class StreamRecorder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "StreamRecorder")

    private let assetWriter: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let outputURL: URL
    private let queue = DispatchQueue(label: "com.multiview.stream-recorder")
    private let isPassthrough: Bool
    private let includeAudio: Bool
    private var started = false
    private var sessionStartTime: CMTime

    let streamName: String

    init(streamName: String, outputURL: URL, isPassthrough: Bool, includeAudio: Bool, sessionStartTime: CMTime) throws {
        self.streamName = streamName
        self.outputURL = outputURL
        self.isPassthrough = isPassthrough
        self.includeAudio = includeAudio
        self.sessionStartTime = sessionStartTime
        self.assetWriter = try AVAssetWriter(url: outputURL, fileType: .mov)
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [self] in
            _appendVideo(sampleBuffer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard includeAudio else { return }
        queue.async { [self] in
            _appendAudio(sampleBuffer)
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard started else {
                    logger.info("Stream '\(self.streamName)' had no samples, skipping finalization")
                    cleanupFile()
                    continuation.resume(returning: nil)
                    return
                }

                guard assetWriter.status == .writing else {
                    logger.error("Asset writer for '\(self.streamName)' in unexpected state: \(self.assetWriter.status.rawValue)")
                    cleanupFile()
                    continuation.resume(returning: nil)
                    return
                }

                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                assetWriter.finishWriting { [self] in
                    if assetWriter.status == .completed {
                        logger.info("Finished recording stream '\(self.streamName)' to \(self.outputURL.lastPathComponent)")
                        continuation.resume(returning: outputURL)
                    } else {
                        logger.error("Failed to finish stream '\(self.streamName)': \(self.assetWriter.error?.localizedDescription ?? "unknown")")
                        cleanupFile()
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func _appendVideo(_ sampleBuffer: CMSampleBuffer) {
        if videoInput == nil {
            if isPassthrough && !Self.isKeyFrame(sampleBuffer) {
                return
            }
            setupVideoInput(from: sampleBuffer)
        }

        guard let videoInput, assetWriter.status == .writing else { return }
        guard videoInput.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts >= sessionStartTime else { return }

        videoInput.append(sampleBuffer)
    }

    private func _appendAudio(_ sampleBuffer: CMSampleBuffer) {
        if audioInput == nil {
            setupAudioInput(from: sampleBuffer)
        }

        guard let audioInput, assetWriter.status == .writing else { return }
        guard audioInput.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts >= sessionStartTime else { return }

        audioInput.append(sampleBuffer)
    }

    private func setupVideoInput(from sampleBuffer: CMSampleBuffer) {
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)

        let input: AVAssetWriterInput
        if isPassthrough {
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDesc)
        } else {
            let dimensions = formatDesc.flatMap { CMVideoFormatDescriptionGetDimensions($0) }
                ?? CMVideoDimensions(width: 1280, height: 720)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000
                ]
            ]
            input = AVAssetWriterInput(mediaType: .video, outputSettings: settings, sourceFormatHint: formatDesc)
        }

        input.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(input) else {
            logger.error("Cannot add video input to asset writer for stream '\(self.streamName)'")
            return
        }

        assetWriter.add(input)
        videoInput = input

        startSessionIfNeeded()
        logger.info("Started recording stream '\(self.streamName)' (passthrough=\(self.isPassthrough))")
    }

    private func setupAudioInput(from sampleBuffer: CMSampleBuffer) {
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: formatDesc)
        input.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(input) else {
            logger.error("Cannot add audio input to asset writer for stream '\(self.streamName)'")
            return
        }

        assetWriter.add(input)
        audioInput = input

        startSessionIfNeeded()
        logger.info("Audio input added for stream '\(self.streamName)'")
    }

    private func startSessionIfNeeded() {
        guard !started else { return }
        guard videoInput != nil, !includeAudio || audioInput != nil else { return }
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: sessionStartTime)
        started = true
    }

    private func cleanupFile() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    private static func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        return !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }
}
