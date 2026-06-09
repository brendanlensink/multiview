import AVFoundation
import Observation

enum OnboardingStep: Int, CaseIterable {
    case camera
    case microphone
    case localNetwork
}

@MainActor
@Observable
final class PermissionManager {
    private static let localNetworkAcknowledgedKey = "multiview-local-network-acknowledged"

    private(set) var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var localNetworkAcknowledged: Bool

    init() {
        localNetworkAcknowledged = UserDefaults.standard.bool(forKey: Self.localNetworkAcknowledgedKey)
    }

    var cameraGranted: Bool { cameraStatus == .authorized }
    var microphoneGranted: Bool { microphoneStatus == .authorized }

    var allMediaPermissionsGranted: Bool { cameraGranted && microphoneGranted }

    var isOnboardingComplete: Bool { allMediaPermissionsGranted && localNetworkAcknowledged }

    // I'd like to integrate the network check here,
    // but it's kind of weird because it's false as soon as onboarding opens
    var hasSeenCameraCheck: Bool {
        cameraStatus == .denied || cameraStatus == .restricted
    }

    var currentOnboardingStep: OnboardingStep? {
        guard !isOnboardingComplete, !hasSeenCameraCheck else { return nil }
        if !cameraGranted { return .camera }
        if !microphoneGranted { return .microphone }
        if !localNetworkAcknowledged { return .localNetwork }
        return nil
    }

    func requestCameraAccess() async {
        if cameraStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = granted ? .authorized : .denied
        }
    }

    func requestMicrophoneAccess() async {
        if microphoneStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .authorized : .denied
        }
    }

    func acknowledgeLocalNetworkAccess() {
        guard !localNetworkAcknowledged else { return }
        localNetworkAcknowledged = true
        UserDefaults.standard.set(true, forKey: Self.localNetworkAcknowledgedKey)
    }

    func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}
