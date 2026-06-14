import AVFoundation
import Observation
import UIKit
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
    private(set) var cameraPosition: AVCaptureDevice.Position = .back

    var canSwitchCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition == .back ? .front : .back) != nil
    }

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

    func applyQualityTier(_ tier: CaptureQualityTier) {
        guard isRunning else { return }

        let preset: AVCaptureSession.Preset
        let bitrate: Int
        switch tier {
        case .full:
            preset = .hd1280x720
            bitrate = 2_000_000
        case .reduced:
            preset = .hd1280x720
            bitrate = 1_000_000
        case .minimal:
            preset = .vga640x480
            bitrate = 500_000
        }

        if captureSession.sessionPreset != preset && captureSession.canSetSessionPreset(preset) {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = preset
            captureSession.commitConfiguration()
            logger.info("Session preset changed to \(preset.rawValue) for tier \(tier.rawValue)")
        }

        encoderBridge.updateBitrate(bitrate)
    }

    func start() {
        guard !isRunning else { return }

        do {
            try configureCaptureSession()
            encoderBridge.start()
            captureSession.startRunning()
            isRunning = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            updateVideoRotation()
            logger.info("Capture session started")
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to start capture session: \(error.localizedDescription)")
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        captureSession.stopRunning()
        encoderBridge.stop()
        isRunning = false
        logger.info("Capture session stopped")
    }

    func switchCamera() {
        guard isRunning else { return }
        let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            logger.warning("No camera available for position \(String(describing: newPosition))")
            return
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if let currentInput = captureSession.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) {
            captureSession.removeInput(currentInput)
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newCamera)
            guard captureSession.canAddInput(newInput) else {
                logger.error("Cannot add video input for \(String(describing: newPosition)) camera")
                return
            }
            captureSession.addInput(newInput)
            cameraPosition = newPosition
            updateVideoRotation()
            encoderBridge.resetEncoder()
            logger.info("Switched to \(newPosition == .front ? "front" : "back") camera")
        } catch {
            logger.error("Failed to switch camera: \(error.localizedDescription)")
        }
    }

    private func configureCaptureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
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
            connection.videoRotationAngle = Self.rotationAngle(for: UIDevice.current.orientation)
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

    @objc private nonisolated func orientationDidChange() {
        Task { @MainActor in
            updateVideoRotation()
        }
    }

    private func updateVideoRotation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        let angle = Self.rotationAngle(for: UIDevice.current.orientation)
        guard connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
        logger.info("Video rotation updated to \(angle)°")
    }

    private static func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
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

    func updateBitrate(_ bitrate: Int) {
        encoder?.updateBitrate(bitrate)
    }

    func resetEncoder() {
        encoder?.invalidate()
        encoder = VideoEncoder()
        encoder?.onEncodedFrame = { [weak self] packet in
            self?.onEncodedFrame?(packet)
        }
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
        case .noCameraAvailable: "No camera available"
        case .noMicrophoneAvailable: "No microphone available"
        case .cannotAddInput: "Cannot add input to session"
        case .cannotAddOutput: "Cannot add output to session"
        }
    }
}
