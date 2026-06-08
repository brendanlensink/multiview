import SwiftUI

struct CameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()

    var body: some View {
        Group {
            if permissionManager.allMediaPermissionsGranted {
                Text("Camera")
                    .font(.largeTitle)
            } else if permissionManager.hasAnyDenied {
                PermissionDeniedView(
                    cameraStatus: permissionManager.cameraStatus,
                    microphoneStatus: permissionManager.microphoneStatus
                )
            } else {
                ProgressView("Requesting permissions...")
            }
        }
        .navigationTitle("Camera")
        .task {
            await permissionManager.requestAllMediaPermissions()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                permissionManager.refreshStatuses()
            }
        }
    }
}

#Preview {
    NavigationStack {
        CameraView()
    }
}
