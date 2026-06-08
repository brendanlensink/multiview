import SwiftUI

struct CameraView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()

    var body: some View {
        Group {
            if permissionManager.allMediaPermissionsGranted {
                cameraContent
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

    private var cameraContent: some View {
        VStack(spacing: 24) {
            Spacer()

            if connectivity.connectionState == .connected {
                connectedView
            } else {
                browsingView
            }

            Spacer()
        }
        .padding()
        .onAppear {
            connectivity.startBrowsing()
        }
        .onDisappear {
            connectivity.stopBrowsing()
        }
        .onChange(of: connectivity.connectionState) {
            if connectivity.connectionState == .connected {
                connectivity.stopBrowsing()
            }
        }
    }

    private var browsingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            Text("Looking for directors…")
                .font(.title2)
                .fontWeight(.medium)

            if !connectivity.discoveredPeers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(connectivity.discoveredPeers, id: \.self) { peer in
                        Button {
                            connectivity.invitePeer(peer)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                Text(peer.displayName)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .padding()
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var connectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            if let director = connectivity.connectedPeers.first {
                Text("Connected to \(director.displayName)")
                    .font(.title2)
                    .fontWeight(.medium)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CameraView()
            .environment(ConnectivityManager())
    }
}
