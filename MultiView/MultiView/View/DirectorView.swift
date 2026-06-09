import AVFoundation
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
    @State private var videoManager = PeerVideoManager()
    @State private var captureManager = CaptureManager()
    @State private var recordingManager = RecordingManager()
    @State private var localDisplayLayer = SampleBufferDisplayLayer()
    @State private var isTransitioning = false
    @State private var recordingStartDate: Date?
    @State private var completedSession: RecordingSession?

    var body: some View {
        directorContent
        .navigationTitle("Director")
        .sheet(item: $completedSession) { session in
            ExportOptionsSheet(session: session) {
                completedSession = nil
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                connectivity.handleAppForegrounded()
            } else if scenePhase == .background {
                if recordingManager.isRecording {
                    videoManager.clearRecordingCallbacks()
                    recordingManager.finalizeAllForBackground()
                    recordingStartDate = nil
                }
                connectivity.handleAppBackgrounded()
            }
        }
    }

    private var directorContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            videoGrid
            recordingOverlay
        }
        .onAppear {
            captureManager.onRawSampleBuffer = { [localDisplayLayer, recordingManager] sampleBuffer in
                localDisplayLayer.enqueue(sampleBuffer)
                recordingManager.appendLocalSample(sampleBuffer)
            }
            captureManager.onAudioSampleBuffer = { [recordingManager] sampleBuffer in
                recordingManager.appendLocalAudio(sampleBuffer)
            }
            captureManager.start()

            connectivity.onFrameReceived = { [videoManager] peer, packet in
                nonisolated(unsafe) let peer = peer
                Task { @MainActor in
                    videoManager.handleFrame(from: peer, packet: packet)
                }
            }
            connectivity.startAdvertising()
        }
        .onDisappear {
            if recordingManager.isRecording {
                videoManager.clearRecordingCallbacks()
                Task { _ = await recordingManager.stopRecording() }
            }

            captureManager.onRawSampleBuffer = nil
            captureManager.onAudioSampleBuffer = nil
            captureManager.stop()

            connectivity.onFrameReceived = nil
            connectivity.stopAdvertising()
            videoManager.removeAllPeers()
        }
        .onChange(of: connectivity.connectedPeers) { oldPeers, newPeers in
            let disconnected = oldPeers.filter { !newPeers.contains($0) }
            for peer in disconnected {
                if recordingManager.isRecording {
                    videoManager.clearRecordingCallback(for: peer)
                    recordingManager.finalizePeerStream(peer)
                }
                videoManager.removePeer(peer)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: captureManager.previewSource)) { notification in
            guard recordingManager.isRecording else { return }
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
                .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                recordingManager.finalizeLocalStream()
            }
        }
    }

    private var recordingOverlay: some View {
        VStack {
            if recordingManager.isRecording, let startDate = recordingStartDate {
                RecordingIndicator(startDate: startDate, lostStreamCount: recordingManager.lostStreamCount)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
            HStack {
                Spacer()
                recordButton
            }
        }
        .animation(.easeInOut(duration: 0.25), value: recordingManager.isRecording)
    }

    private var recordButton: some View {
        Button {
            if recordingManager.isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Circle()
                .fill(recordingManager.isRecording ? .red : .white)
                .frame(width: 28, height: 28)
                .overlay {
                    if recordingManager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(6)
                .background(.black.opacity(0.5), in: Circle())
        }
        .disabled(isTransitioning)
        .opacity(isTransitioning ? 0.5 : 1)
        .padding(16)
    }

    private func startRecording() {
        guard !isTransitioning else { return }
        isTransitioning = true

        let peers = connectivity.connectedPeers
        let localName = connectivity.peerID.displayName
        recordingManager.startRecording(localPeerName: localName, remotePeers: peers)

        for peer in peers {
            videoManager.setRecordingCallback(for: peer) { [recordingManager] sampleBuffer in
                recordingManager.appendPeerSample(sampleBuffer, from: peer)
            }
        }

        recordingStartDate = Date()
        isTransitioning = false
    }

    private func stopRecording() {
        guard !isTransitioning else { return }
        isTransitioning = true
        videoManager.clearRecordingCallbacks()
        Task {
            let session = await recordingManager.stopRecording()
            recordingStartDate = nil
            isTransitioning = false
            completedSession = session
        }
    }

    private var videoGrid: some View {
        let peers = connectivity.connectedPeers
        let totalCells = peers.count + 1

        return GeometryReader { geometry in
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

// MARK: - Recording Indicator

private struct RecordingIndicator: View {
    let startDate: Date
    var lostStreamCount = 0
    @State private var dotVisible = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(dotVisible ? 1 : 0.3)

            Text(startDate, style: .timer)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)

            if lostStreamCount > 0 {
                Text("\(lostStreamCount) lost")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6), in: Capsule())
        .padding(.top, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                dotVisible = false
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
