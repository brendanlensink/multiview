import SwiftUI

struct DirectorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()

    var body: some View {
        Group {
            if permissionManager.allMediaPermissionsGranted {
                Text("Director")
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
        .navigationTitle("Director")
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
        DirectorView()
    }
}
