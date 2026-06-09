#if targetEnvironment(simulator)
import CoreGraphics
import CoreMedia
import CoreVideo
import UIKit

enum TestPatternColor: CaseIterable {
    case blue, green, orange, purple

    var uiColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .purple: .systemPurple
        }
    }
}

enum TestPatternGenerator {
    static let width = 1280
    static let height = 720

    static func createPixelBuffer(label: String, color: TestPatternColor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        drawTestPattern(in: context, label: label, color: color)
        return buffer
    }

    static func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    // MARK: - Drawing

    private static let barColors: [UIColor] = [
        .white, .yellow, .cyan, .green, .magenta, .red, .blue
    ]

    private static func drawTestPattern(in context: CGContext, label: String, color: TestPatternColor) {
        let w = CGFloat(width)
        let h = CGFloat(height)

        context.setFillColor(color.uiColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let barWidth = w / CGFloat(barColors.count)
        let barHeight = h * 0.15
        for (i, barColor) in barColors.enumerated() {
            context.setFillColor(barColor.withAlphaComponent(0.6).cgColor)
            context.fill(CGRect(x: CGFloat(i) * barWidth, y: h - barHeight, width: barWidth, height: barHeight))
        }

        let borderInset: CGFloat = 20
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(2)
        context.stroke(CGRect(x: borderInset, y: borderInset, width: w - borderInset * 2, height: h - borderInset * 2))

        drawCrosshair(in: context, center: CGPoint(x: w / 2, y: h / 2), size: 60)

        UIGraphicsPushContext(context)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = CGRect(
            x: (w - textSize.width) / 2,
            y: (h - textSize.height) / 2 - 40,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle,
        ]
        let subtitle = "SIMULATOR" as NSString
        let subSize = subtitle.size(withAttributes: subtitleAttrs)
        let subRect = CGRect(
            x: (w - subSize.width) / 2,
            y: (h - subSize.height) / 2 + 20,
            width: subSize.width,
            height: subSize.height
        )
        subtitle.draw(in: subRect, withAttributes: subtitleAttrs)
        UIGraphicsPopContext()
    }

    private static func drawCrosshair(in context: CGContext, center: CGPoint, size: CGFloat) {
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: center.x - size, y: center.y))
        context.addLine(to: CGPoint(x: center.x + size, y: center.y))
        context.move(to: CGPoint(x: center.x, y: center.y - size))
        context.addLine(to: CGPoint(x: center.x, y: center.y + size))
        context.strokePath()
    }
}
#endif
