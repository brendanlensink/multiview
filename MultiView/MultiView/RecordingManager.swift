import AVFoundation
import Observation
import os

@MainActor @Observable
final class RecordingManager {
    private nonisolated let logger = Logger(subsystem: "com.multiview", category: "Recording")

    private(set) var isRecording = false
    private(set) var recordingURL: URL?
    private(set) var error: String?

    private nonisolated let writer = AssetWriterBridge()

    func startRecording() {
        guard !isRecording else { return }

        let fileName = "MultiView-\(Self.dateFormatter.string(from: Date())).mov"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try writer.configure(outputURL: url)
            recordingURL = url
            isRecording = true
            logger.info("Recording started: \(url.lastPathComponent)")
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false

        let url = await writer.finish()
        logger.info("Recording finished: \(url?.lastPathComponent ?? "nil")")
        return url
    }

    nonisolated func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writer.appendVideo(sampleBuffer)
    }

    nonisolated func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writer.appendAudio(sampleBuffer)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()
}

// MARK: - AssetWriterBridge

private final class AssetWriterBridge: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "AssetWriter")
    private let queue = DispatchQueue(label: "com.multiview.asset-writer")

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false

    func configure(outputURL: URL) throws {
        try queue.sync {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 720,
                AVVideoHeightKey: 1280,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
                ]
            ]
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            video.expectsMediaDataInRealTime = true

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true

            guard writer.canAdd(video) else { throw RecordingError.cannotAddVideoInput }
            writer.add(video)

            guard writer.canAdd(audio) else { throw RecordingError.cannotAddAudioInput }
            writer.add(audio)

            self.assetWriter = writer
            self.videoInput = video
            self.audioInput = audio
            self.sessionStarted = false
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.append(sampleBuffer, to: self?.videoInput, isVideo: true)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.append(sampleBuffer, to: self?.audioInput, isVideo: false)
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let writer = self.assetWriter else {
                    continuation.resume(returning: nil)
                    return
                }

                let url = writer.outputURL
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                writer.finishWriting {
                    if writer.status == .failed {
                        self.logger.error("Asset writer failed: \(writer.error?.localizedDescription ?? "unknown")")
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: url)
                    }
                    self.assetWriter = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    self.sessionStarted = false
                }
            }
        }
    }

    // MARK: - Private

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?, isVideo: Bool) {
        guard let writer = assetWriter, let input else { return }

        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        guard writer.status == .writing else {
            if writer.status == .failed {
                logger.error("Asset writer error: \(writer.error?.localizedDescription ?? "unknown")")
            }
            return
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case cannotAddVideoInput
    case cannotAddAudioInput

    var errorDescription: String? {
        switch self {
        case .cannotAddVideoInput: "Cannot add video input to asset writer"
        case .cannotAddAudioInput: "Cannot add audio input to asset writer"
        }
    }
}
