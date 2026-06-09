import SwiftUI

struct OnboardingView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        Group {
            if permissionManager.hasSeenCameraCheck {
                PermissionDeniedView(
                    cameraStatus: permissionManager.cameraStatus,
                    microphoneStatus: permissionManager.microphoneStatus
                )
            } else if let step = permissionManager.currentOnboardingStep {
                OnboardingStepView(step: step)
            }
        }
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(PermissionManager())
        .environment(ConnectivityManager())
}

#Preview("Denied") {
    OnboardingView()
        .environment(PermissionManager())
        .environment(ConnectivityManager())
}
