import AVFoundation
import Observation

@MainActor
@Observable
final class PermissionManager {
    private(set) var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var cameraGranted: Bool { cameraStatus == .authorized }
    var microphoneGranted: Bool { microphoneStatus == .authorized }

    var allMediaPermissionsGranted: Bool { cameraGranted && microphoneGranted }

    var hasAnyDenied: Bool {
        cameraStatus == .denied || cameraStatus == .restricted ||
        microphoneStatus == .denied || microphoneStatus == .restricted
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

    func requestAllMediaPermissions() async {
        await requestCameraAccess()
        await requestMicrophoneAccess()
    }

    func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}
