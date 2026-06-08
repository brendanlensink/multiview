import VideoToolbox
import os

final class VideoDecoder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "VideoDecoder")

    private var formatDescription: CMFormatDescription?
    var onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    var onRecordSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    func decode(packet: FramePacket) {
        if packet.isKeyFrame, let paramData = packet.parameterSets {
            updateFormatDescription(from: paramData)
        }

        guard let formatDesc = formatDescription else {
            logger.debug("Waiting for keyframe with parameter sets")
            return
        }

        guard let blockBuffer = createBlockBuffer(from: packet.payload) else { return }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(packet.presentationTime), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )

        let status = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            logger.error("CMSampleBufferCreateReady failed: \(status)")
            return
        }

        onSampleBuffer?(sampleBuffer)
        onRecordSampleBuffer?(sampleBuffer)
    }

    func invalidate() {
        formatDescription = nil
    }

    deinit {
        invalidate()
    }

    // MARK: - Private

    private func updateFormatDescription(from paramData: Data) {
        let parameterSets = Self.parseParameterSets(paramData)
        guard parameterSets.count >= 2 else { return }

        var newFormatDesc: CMFormatDescription?
        let sizes = parameterSets.map { $0.count }
        let status = parameterSets.withUnsafeBufferPointers { pointers in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers.baseAddress!,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &newFormatDesc
            )
        }

        guard status == noErr, let newFormatDesc else {
            logger.error("Failed to create format description: \(status)")
            return
        }

        if formatDescription == nil || !CMFormatDescriptionEqual(formatDescription!, otherFormatDescription: newFormatDesc) {
            formatDescription = newFormatDesc
        }
    }

    private func createBlockBuffer(from data: Data) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        let length = data.count

        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, let buffer = blockBuffer else { return nil }

        status = data.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: length
            )
        }

        return status == noErr ? buffer : nil
    }

    private static func parseParameterSets(_ data: Data) -> [Data] {
        var sets: [Data] = []
        var offset = 0
        while offset + 2 <= data.count {
            let length = Int(data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            offset += 2
            guard offset + length <= data.count else { break }
            sets.append(data.subdata(in: offset..<(offset + length)))
            offset += length
        }
        return sets
    }
}

// MARK: - Helper for passing parameter set pointers to C API

private extension Array where Element == Data {
    func withUnsafeBufferPointers<R>(_ body: (UnsafeBufferPointer<UnsafePointer<UInt8>>) -> R) -> R {
        var pointers: [UnsafePointer<UInt8>] = []
        func recurse(index: Int, accumulated: inout [UnsafePointer<UInt8>]) -> R {
            if index == count {
                return accumulated.withUnsafeBufferPointer { body($0) }
            }
            return self[index].withUnsafeBytes { rawBuffer in
                accumulated.append(rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self))
                return recurse(index: index + 1, accumulated: &accumulated)
            }
        }
        return recurse(index: 0, accumulated: &pointers)
    }
}
