import AVFoundation

enum CaptureQualityPreset: String, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var subtitle: String {
        switch self {
        case .high: "1080p · 8 Mbps"
        case .medium: "720p · 4 Mbps"
        case .low: "480p · 2 Mbps"
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
