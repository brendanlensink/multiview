import SwiftUI

struct DirectorView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionManager = PermissionManager()
    @State private var videoManager = PeerVideoManager()
    @State private var captureManager = CaptureManager()
    @State private var localDisplayLayer = SampleBufferDisplayLayer()

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
            videoGrid
        }
        .onAppear {
            captureManager.onRawSampleBuffer = { [localDisplayLayer] sampleBuffer in
                DispatchQueue.main.async {
                    localDisplayLayer.enqueue(sampleBuffer)
                }
            }
            captureManager.start()

            connectivity.onFrameReceived = { [videoManager] peer, packet in
                Task { @MainActor in
                    videoManager.handleFrame(from: peer, packet: packet)
                }
            }
            connectivity.startAdvertising()
        }
        .onDisappear {
            captureManager.onRawSampleBuffer = nil
            captureManager.stop()

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

    private var videoGrid: some View {
        let peers = connectivity.connectedPeers
        let totalCells = peers.count + 1
        let columns = totalCells <= 1 ? 1 : 2

        return GeometryReader { geometry in
            let rows = (totalCells + columns - 1) / columns
            let cellWidth = geometry.size.width / CGFloat(columns)
            let cellHeight = geometry.size.height / CGFloat(rows)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: columns),
                spacing: 0
            ) {
                PeerVideoCell(
                    peerName: "Director",
                    displayLayer: localDisplayLayer,
                    isLocal: true
                )
                .frame(width: cellWidth, height: cellHeight)

                ForEach(peers, id: \.self) { peer in
                    PeerVideoCell(
                        peerName: peer.displayName,
                        displayLayer: videoManager.displayLayers[peer]
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
    let displayLayer: SampleBufferDisplayLayer?
    var isLocal = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let displayLayer {
                SampleBufferVideoView(layer: displayLayer)
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
        .overlay {
            if isLocal {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.blue, lineWidth: 2)
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
