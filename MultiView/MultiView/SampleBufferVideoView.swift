import AVFoundation
import SwiftUI
import os

final class SampleBufferDisplayLayer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.multiview", category: "DisplayLayer")

    let displayLayer = AVSampleBufferDisplayLayer()
    private var needsFlush = false

    init() {
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.preventsDisplaySleepDuringVideoPlayback = true
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if needsFlush {
            displayLayer.flush()
            needsFlush = false
        }

        if displayLayer.status == .failed {
            logger.warning("Display layer failed: \(String(describing: self.displayLayer.error)), flushing")
            displayLayer.flush()
        }

        displayLayer.enqueue(sampleBuffer)
    }

    func flush() {
        needsFlush = true
    }
}

struct SampleBufferVideoView: UIViewRepresentable {
    let layer: SampleBufferDisplayLayer

    func makeUIView(context: Context) -> SampleBufferUIView {
        let view = SampleBufferUIView()
        view.displayLayer = layer.displayLayer
        return view
    }

    func updateUIView(_ uiView: SampleBufferUIView, context: Context) {
        if uiView.displayLayer !== layer.displayLayer {
            uiView.displayLayer = layer.displayLayer
        }
    }
}

final class SampleBufferUIView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer? {
        didSet {
            guard displayLayer !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let displayLayer {
                displayLayer.frame = bounds
                layer.addSublayer(displayLayer)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer?.frame = bounds
        CATransaction.commit()
    }
}
