import AVFoundation
import Observation
import os

@MainActor @Observable
final class CaptureManager: NSObject {
    private nonisolated let logger = Logger(subsystem: "com.multiview", category: "Capture")

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let outputQueue = DispatchQueue(label: "com.multiview.capture-output")
    private nonisolated let encoderBridge = EncoderBridge()

    private(set) var isRunning = false
    private(set) var error: String?

    var onRawSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)? {
        get { encoderBridge.onRawSampleBuffer }
        set { encoderBridge.onRawSampleBuffer = newValue }
    }

    var onAudioSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)? {
        get { encoderBridge.onAudioSampleBuffer }
        set { encoderBridge.onAudioSampleBuffer = newValue }
    }

    var onEncodedFrame: (@Sendable (FramePacket) -> Void)? {
        didSet { encoderBridge.onEncodedFrame = onEncodedFrame }
    }

    var previewSource: AVCaptureSession { captureSession }

    func start() {
        guard !isRunning else { return }

        do {
            try configureCaptureSession()
            encoderBridge.start()
            captureSession.startRunning()
            isRunning = true
            logger.info("Capture session started")
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to start capture session: \(error.localizedDescription)")
        }
    }

    func stop() {
        captureSession.stopRunning()
        encoderBridge.stop()
        isRunning = false
        logger.info("Capture session stopped")
    }

    private func configureCaptureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.noCameraAvailable
        }

        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(videoInput) else {
            throw CaptureError.cannotAddInput
        }
        captureSession.addInput(videoInput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            throw CaptureError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw CaptureError.noMicrophoneAvailable
        }

        let audioInput = try AVCaptureDeviceInput(device: microphone)
        guard captureSession.canAddInput(audioInput) else {
            throw CaptureError.cannotAddInput
        }
        captureSession.addInput(audioInput)

        audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(audioOutput) else {
            throw CaptureError.cannotAddOutput
        }
        captureSession.addOutput(audioOutput)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            encoderBridge.onAudioSampleBuffer?(sampleBuffer)
            return
        }

        encoderBridge.onRawSampleBuffer?(sampleBuffer)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoderBridge.encode(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        logger.debug("Dropped frame")
    }
}

// MARK: - EncoderBridge

private final class EncoderBridge: @unchecked Sendable {
    private var encoder: VideoEncoder?
    var onRawSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    var onAudioSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    var onEncodedFrame: (@Sendable (FramePacket) -> Void)?

    func start() {
        encoder = VideoEncoder()
        encoder?.onEncodedFrame = { [weak self] packet in
            self?.onEncodedFrame?(packet)
        }
    }

    func stop() {
        encoder?.invalidate()
        encoder = nil
    }

    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        encoder?.encode(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noCameraAvailable
    case noMicrophoneAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: "No back camera available"
        case .noMicrophoneAvailable: "No microphone available"
        case .cannotAddInput: "Cannot add input to session"
        case .cannotAddOutput: "Cannot add output to session"
        }
    }
}
