import AVFoundation
import MultipeerConnectivity
import SwiftUI

// MARK: - Director View

struct DirectorView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var videoManager = PeerVideoManager()
    @State private var captureManager = CaptureManager()
    @State private var recordingManager = RecordingManager()
    @State private var conditionManager = DeviceConditionManager()
    @State private var localDisplayLayer = SampleBufferDisplayLayer()
    @State private var isTransitioning = false
    @State private var recordingStartDate: Date?
    @State private var completedSession: RecordingSession?
    @State private var disconnectedPeers: Set<MCPeerID> = []
    @State private var disconnectTimers: [MCPeerID: Task<Void, Never>] = [:]
    @State private var layoutManager = FeedLayoutManager()
    @State private var showingCameraList = false
    #if targetEnvironment(simulator)
    @State private var simulatorSession: SimulatorSession?
    #endif

    var body: some View {
        directorContent
        .navigationTitle("Director")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                cameraListButton
            }
        }
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
            #if targetEnvironment(simulator)
            let session = SimulatorSession(
                peerVideoManager: videoManager,
                localDisplayLayer: localDisplayLayer,
                connectivity: connectivity
            )
            simulatorSession = session
            session.start()
            #else
            captureManager.onRawSampleBuffer = { [localDisplayLayer] sampleBuffer in
                localDisplayLayer.enqueue(sampleBuffer)
            }
            captureManager.onEncodedSampleBuffer = { [recordingManager] sampleBuffer in
                recordingManager.appendLocalSample(sampleBuffer)
            }
            captureManager.onAudioSampleBuffer = { [recordingManager] sampleBuffer in
                recordingManager.appendLocalAudio(sampleBuffer)
            }
            captureManager.start()
            conditionManager.startMonitoring()

            connectivity.onFrameReceived = { [videoManager] peer, packet in
                nonisolated(unsafe) let peer = peer
                Task { @MainActor in
                    videoManager.handleFrame(from: peer, packet: packet)
                }
            }
            connectivity.startAdvertising()
            #endif
        }
        .onDisappear {
            #if targetEnvironment(simulator)
            simulatorSession?.stop()
            simulatorSession = nil
            #else
            if recordingManager.isRecording {
                videoManager.clearRecordingCallbacks()
                Task { _ = await recordingManager.stopRecording() }
            }

            captureManager.onRawSampleBuffer = nil
            captureManager.onEncodedSampleBuffer = nil
            captureManager.onAudioSampleBuffer = nil
            captureManager.stop()
            conditionManager.stopMonitoring()
            #endif

            for timer in disconnectTimers.values { timer.cancel() }
            disconnectTimers.removeAll()
            disconnectedPeers.removeAll()

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
                showDisconnectedState(for: peer)
            }

            let reconnected = newPeers.filter { disconnectedPeers.contains($0) }
            for peer in reconnected {
                disconnectTimers[peer]?.cancel()
                disconnectTimers.removeValue(forKey: peer)
                withAnimation(.easeInOut(duration: 0.3)) {
                    disconnectedPeers.remove(peer)
                }
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
        .onChange(of: conditionManager.qualityTier) {
            captureManager.applyQualityTier(conditionManager.qualityTier)
        }
    }

    private var recordingOverlay: some View {
        VStack {
            ThrottleIndicator(tier: conditionManager.qualityTier)
                .animation(.easeInOut, value: conditionManager.qualityTier)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            VStack(spacing: 12) {
                if recordingManager.isRecording, let startDate = recordingStartDate {
                    RecordingIndicator(startDate: startDate, lostStreamCount: recordingManager.lostStreamCount)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                recordButton
            }
            .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.25), value: recordingManager.isRecording)
    }

    private var cameraListButton: some View {
        Button {
            showingCameraList = true
        } label: {
            Image(systemName: "video.fill")
        }
        .popover(isPresented: $showingCameraList) {
            CameraListPopover(
                layoutManager: layoutManager,
                allFeedIDs: allFeedIDs,
                canSwitchDirectorCamera: captureManager.canSwitchCamera,
                onSwitchDirectorCamera: { captureManager.switchCamera() }
            )
        }
    }

    private var recordButton: some View {
        Button {
            if recordingManager.isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 68, height: 68)

                if recordingManager.isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 58, height: 58)
                }
            }
        }
        .disabled(isTransitioning)
        .opacity(isTransitioning ? 0.5 : 1)
    }

    private func showDisconnectedState(for peer: MCPeerID) {
        disconnectTimers[peer]?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            disconnectedPeers.insert(peer)
        }
        disconnectTimers[peer] = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                disconnectedPeers.remove(peer)
                layoutManager.hiddenFeeds.remove(.peer(peer))
            }
            disconnectTimers.removeValue(forKey: peer)
            videoManager.removePeer(peer)
        }
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

    private var allFeedIDs: [FeedID] {
        let connectedPeers = connectivity.connectedPeers
        let allVisiblePeers = connectedPeers + disconnectedPeers.filter { !connectedPeers.contains($0) }
        return [.director] + allVisiblePeers.map { .peer($0) }
    }

    private var visibleFeedIDs: [FeedID] {
        allFeedIDs.filter { !layoutManager.hiddenFeeds.contains($0) }
    }

    private var videoGrid: some View {
        let visiblePeers = connectivity.connectedPeers.filter { !layoutManager.hiddenFeeds.contains(.peer($0)) }
        let visibleDisconnected = disconnectedPeers.filter { !connectivity.connectedPeers.contains($0) && !layoutManager.hiddenFeeds.contains(.peer($0)) }
        let allVisiblePeers = visiblePeers + visibleDisconnected

        return GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layoutManager.editingFeedID = nil
                        }
                    }

                if !layoutManager.hiddenFeeds.contains(.director) {
                    InteractiveFeedCell(
                        feedID: .director,
                        layoutManager: layoutManager,
                        peerName: "Director",
                        displayLayer: localDisplayLayer,
                        isLocal: true
                    )
                }

                ForEach(allVisiblePeers, id: \.self) { peer in
                    InteractiveFeedCell(
                        feedID: .peer(peer),
                        layoutManager: layoutManager,
                        peerName: peer.displayName,
                        displayLayer: videoManager.displayLayers[peer],
                        isDisconnected: disconnectedPeers.contains(peer)
                    )
                    .transition(.opacity)
                }
            }
            .onAppear {
                layoutManager.recalculateGrid(feeds: visibleFeedIDs, in: geometry.size)
            }
            .onChange(of: allVisiblePeers) {
                layoutManager.recalculateGrid(feeds: visibleFeedIDs, in: geometry.size)
            }
            .onChange(of: layoutManager.hiddenFeeds) {
                layoutManager.recalculateGrid(feeds: visibleFeedIDs, in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                layoutManager.recalculateGrid(feeds: visibleFeedIDs, in: newSize)
            }
        }
    }
}

// MARK: - Interactive Feed Cell

private struct InteractiveFeedCell: View {
    let feedID: FeedID
    let layoutManager: FeedLayoutManager
    let peerName: String
    let displayLayer: SampleBufferDisplayLayer?
    var isLocal: Bool = false
    var isDisconnected: Bool = false

    @State private var dragAnchor: CGPoint?
    @State private var pinchAnchor: CGSize?

    var body: some View {
        if let frame = layoutManager.frames[feedID] {
            let isEditing = layoutManager.editingFeedID == feedID
            let isActive = layoutManager.activeFeedID == feedID
            PeerVideoCell(
                peerName: peerName,
                displayLayer: displayLayer,
                isLocal: isLocal,
                isDisconnected: isDisconnected
            )
            .frame(width: frame.size.width, height: frame.size.height)
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.red, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            layoutManager.hiddenFeeds.insert(feedID)
                            layoutManager.editingFeedID = nil
                        }
                    } label: {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.7), in: Circle())
                    }
                    .padding(6)
                }
            }
            .position(frame.center)
            .zIndex(isEditing ? 1 : 0)
            .animation(isActive ? nil : .easeOut(duration: 0.15), value: frame)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layoutManager.editingFeedID = isEditing ? nil : feedID
                }
            }
            .gesture(
                isEditing
                ? DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if dragAnchor == nil {
                            dragAnchor = layoutManager.frames[feedID]?.center
                        }
                        guard let anchor = dragAnchor else { return }
                        layoutManager.setFeedCenter(feedID, CGPoint(
                            x: anchor.x + value.translation.width,
                            y: anchor.y + value.translation.height
                        ))
                    }
                    .onEnded { _ in
                        dragAnchor = nil
                        layoutManager.endGesture()
                    }
                : nil
            )
            .simultaneousGesture(
                isEditing
                ? MagnifyGesture()
                    .onChanged { value in
                        if pinchAnchor == nil {
                            pinchAnchor = layoutManager.frames[feedID]?.size
                        }
                        guard let anchor = pinchAnchor else { return }
                        layoutManager.setFeedSize(feedID, CGSize(
                            width: anchor.width * value.magnification,
                            height: anchor.height * value.magnification
                        ))
                    }
                    .onEnded { _ in
                        pinchAnchor = nil
                        layoutManager.endGesture()
                    }
                : nil
            )
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
    var isDisconnected = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let displayLayer {
                SampleBufferVideoView(layer: displayLayer)
            } else {
                Color.black
                ProgressView()
                    .tint(.white)
            }

            if isDisconnected {
                Color.black.opacity(0.6)
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                    Text("Disconnected")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Camera List Popover

private struct CameraListPopover: View {
    let layoutManager: FeedLayoutManager
    let allFeedIDs: [FeedID]
    var canSwitchDirectorCamera = false
    var onSwitchDirectorCamera: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cameras")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(Array(allFeedIDs.enumerated()), id: \.element) { _, feedID in
                let isHidden = layoutManager.hiddenFeeds.contains(feedID)
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if isHidden {
                                layoutManager.hiddenFeeds.remove(feedID)
                            } else {
                                layoutManager.hiddenFeeds.insert(feedID)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: feedID == .director ? "video.fill" : "camera.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(feedID.displayName)
                                .foregroundStyle(isHidden ? .secondary : .primary)
                            Spacer()
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .foregroundColor(isHidden ? .secondary : .blue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if feedID == .director, canSwitchDirectorCamera {
                        Button {
                            onSwitchDirectorCamera?()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .padding(.bottom, 12)
        .frame(minWidth: 220)
        .presentationCompactAdaptation(.popover)
    }
}

#Preview {
    NavigationStack {
        DirectorView()
            .environment(ConnectivityManager())
    }
}
