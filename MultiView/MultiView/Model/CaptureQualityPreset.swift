import AVFoundation

enum CaptureQualityPreset: String, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: "High (1080p)"
        case .medium: "Medium (720p)"
        case .low: "Low (480p)"
        }
    }

    var subtitle: String {
        switch self {
        case .high: "Best quality, uses more battery"
        case .medium: "Balanced quality and performance"
        case .low: "Saves battery and bandwidth"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .high: .hd1920x1080
        case .medium: .hd1280x720
        case .low: .vga640x480
        }
    }

    var baseBitrate: Int {
        switch self {
        case .high: 4_000_000
        case .medium: 2_000_000
        case .low: 500_000
        }
    }
}
