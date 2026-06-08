import SwiftUI

struct CameraView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()
    @State private var captureManager = CaptureManager()

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
        ZStack {
            CameraPreviewView(session: captureManager.previewSource)
                .ignoresSafeArea()

            VStack {
                Spacer()
                connectionOverlay
                    .padding()
            }
        }
        .onAppear {
            captureManager.start()
            connectivity.startBrowsing()
        }
        .onDisappear {
            captureManager.stop()
            connectivity.stopBrowsing()
        }
        .onChange(of: connectivity.connectionState) {
            if connectivity.connectionState == .connected {
                connectivity.stopBrowsing()
            }
        }
    }

    @ViewBuilder
    private var connectionOverlay: some View {
        if connectivity.connectionState == .connected {
            if let director = connectivity.connectedPeers.first {
                Label("Connected to \(director.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            VStack(spacing: 12) {
                if connectivity.discoveredPeers.isEmpty {
                    Label("Looking for directors…", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
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
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    NavigationStack {
        CameraView()
            .environment(ConnectivityManager())
    }
}
