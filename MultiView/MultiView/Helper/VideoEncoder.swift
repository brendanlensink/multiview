import VideoToolbox
import os

final class VideoEncoder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "VideoEncoder")

    private var compressionSession: VTCompressionSession?
    private var sessionWidth: Int32 = 0
    private var sessionHeight: Int32 = 0
    var onEncodedFrame: (@Sendable (FramePacket) -> Void)?

    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

        if compressionSession == nil || width != sessionWidth || height != sessionHeight {
            setupSession(width: width, height: height)
        }

        guard let session = compressionSession else { return }

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sampleBuffer in
                guard status == noErr, let sampleBuffer else {
                    self?.logger.error("Encode failed with status: \(status)")
                    return
                }
                self?.handleEncodedFrame(sampleBuffer)
            }
        )

        if status != noErr {
            logger.error("VTCompressionSessionEncodeFrame failed: \(status)")
        }
    }

    func invalidate() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        compressionSession = nil
    }

    deinit {
        invalidate()
    }

    // MARK: - Private

    private func setupSession(width: Int32, height: Int32) {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let session = compressionSession else {
            logger.error("Failed to create compression session: \(status)")
            return
        }

        sessionWidth = width
        sessionHeight = height

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        logger.info("Video encoder configured: \(width)x\(height) H.264 Main profile")
    }

    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard status == noErr, let pointer = dataPointer else { return }

        let payload = Data(bytes: pointer, count: totalLength)

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyFrame = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsNanos = UInt64(pts.seconds * 1_000_000_000)

        var parameterSets: Data?
        if isKeyFrame, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSets = Self.extractParameterSets(from: formatDesc)
        }

        let packet = FramePacket(
            isKeyFrame: isKeyFrame,
            presentationTime: ptsNanos,
            parameterSets: parameterSets,
            payload: payload
        )
        onEncodedFrame?(packet)
    }

    private static func extractParameterSets(from formatDesc: CMFormatDescription) -> Data? {
        var count: Int = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil) == noErr else {
            return nil
        }

        var data = Data()
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size: Int = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: i, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
                  let ptr else { continue }
            var len = UInt16(size).bigEndian
            data.append(Data(bytes: &len, count: 2))
            data.append(Data(bytes: ptr, count: size))
        }
        return data.isEmpty ? nil : data
    }
}
