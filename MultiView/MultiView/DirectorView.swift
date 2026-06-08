import SwiftUI

// MARK: - Grid Layout

private struct GridLayout {
    let columns: Int
    let rows: Int

    static func forPeerCount(_ count: Int, in size: CGSize) -> GridLayout {
        switch count {
        case 0, 1:
            return GridLayout(columns: 1, rows: 1)
        case 2:
            let isLandscape = size.width > size.height
            return GridLayout(columns: isLandscape ? 2 : 1, rows: isLandscape ? 1 : 2)
        default:
            let rows = (count + 1) / 2
            return GridLayout(columns: 2, rows: rows)
        }
    }

    func cellFrame(at index: Int, in size: CGSize) -> CGRect {
        let col = index % columns
        let row = index / columns
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        return CGRect(
            x: CGFloat(col) * cellWidth,
            y: CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }
}

// MARK: - Director View

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

        GeometryReader { geometry in
            let size = geometry.size
            let grid = GridLayout.forPeerCount(totalCells, in: size)
            let directorCell = grid.cellFrame(at: 0, in: size)

            ZStack {
                PeerVideoCell(
                    peerName: "Director",
                    displayLayer: localDisplayLayer,
                    isLocal: true
                )
                .frame(width: directorCell.width, height: directorCell.height)
                .position(x: directorCell.midX, y: directorCell.midY)

                ForEach(Array(peers.enumerated()), id: \.element) { index, peer in
                    let cell = grid.cellFrame(at: index + 1, in: size)

                    PeerVideoCell(
                        peerName: peer.displayName,
                        displayLayer: videoManager.displayLayers[peer]
                    )
                    .frame(width: cell.width, height: cell.height)
                    .position(x: cell.midX, y: cell.midY)
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: peers)
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
