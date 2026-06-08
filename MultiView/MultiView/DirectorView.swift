import SwiftUI

struct DirectorView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()

    var body: some View {
        Group {
            if permissionManager.allMediaPermissionsGranted {
                directorContent
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

    private var directorContent: some View {
        VStack(spacing: 24) {
            Spacer()

            connectionStatusView

            if !connectivity.connectedPeers.isEmpty {
                connectedPeersList
            }

            Spacer()
        }
        .padding()
        .onAppear {
            connectivity.startAdvertising()
        }
        .onDisappear {
            connectivity.stopAdvertising()
        }
    }

    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            Image(systemName: connectivity.connectedPeers.isEmpty ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(connectivity.connectedPeers.isEmpty ? .blue : .green)
                .symbolEffect(.pulse, options: .repeating, isActive: connectivity.connectedPeers.isEmpty)

            Text(connectivity.connectedPeers.isEmpty ? "Waiting for cameras…" : "\(connectivity.connectedPeers.count) camera\(connectivity.connectedPeers.count == 1 ? "" : "s") connected")
                .font(.title2)
                .fontWeight(.medium)
        }
    }

    private var connectedPeersList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(connectivity.connectedPeers, id: \.self) { peer in
                HStack {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.green)
                    Text(peer.displayName)
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DirectorView()
            .environment(ConnectivityManager())
    }
}
