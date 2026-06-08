import SwiftUI

struct DirectorView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()
    @State private var videoManager = PeerVideoManager()

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
                connectivity.handleAppForegrounded()
            } else if scenePhase == .background {
                connectivity.handleAppBackgrounded()
            }
        }
    }

    private var directorContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if connectivity.connectedPeers.isEmpty {
                waitingView
            } else {
                videoGrid
            }
        }
        .onAppear {
            connectivity.onFrameReceived = { [videoManager] peer, packet in
                Task { @MainActor in
                    videoManager.handleFrame(from: peer, packet: packet)
                }
            }
            connectivity.startAdvertising()
        }
        .onDisappear {
            connectivity.onFrameReceived = nil
            connectivity.stopAdvertising()
            videoManager.removeAllPeers()
        }
        .onChange(of: connectivity.connectedPeers) { oldPeers, newPeers in
            let disconnected = oldPeers.filter { !newPeers.contains($0) }
            for peer in disconnected {
                videoManager.removePeer(peer)
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            Text("Waiting for cameras…")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }

    private var videoGrid: some View {
        let peers = connectivity.connectedPeers
        let columns = peers.count <= 1 ? 1 : 2

        return GeometryReader { geometry in
            let rows = (peers.count + columns - 1) / columns
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: columns),
                spacing: 0
            ) {
                ForEach(peers, id: \.self) { peer in
                    PeerVideoCell(
                        peerName: peer.displayName,
                        frame: videoManager.latestFrames[peer]
                    )
                    .frame(width: cellWidth, height: cellHeight)
                }
            }
        }
    }
}

// MARK: - Video Cell

private struct PeerVideoCell: View {
    let peerName: String
    let frame: CGImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let frame {
                Image(decorative: frame, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
                ProgressView()
                    .tint(.white)
            }

            Text(peerName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
                .padding(8)
        }
        .clipped()
    }
}

#Preview {
    NavigationStack {
        DirectorView()
            .environment(ConnectivityManager())
    }
}
