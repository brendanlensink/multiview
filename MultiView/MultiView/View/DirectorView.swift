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
            HStack {
                VStack(alignment: .leading, spacing: Theme.Padding.s) {
                    if recordingManager.isRecording, let startDate = recordingStartDate {
                        RecordingIndicator(startDate: startDate, lostStreamCount: recordingManager.lostStreamCount)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ThrottleIndicator(tier: conditionManager.qualityTier)
                        .animation(.easeInOut, value: conditionManager.qualityTier)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Padding.m)
            .padding(.top, Theme.Padding.s)

            Spacer()
            recordButton
                .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.25), value: recordingManager.isRecording)
    }

    private var cameraListButton: some View {
        Button {
            showingCameraList = true
        } label: {
            Image(systemName: "square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
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

            HStack(spacing: 6) {
                Text(startDate, style: .timer)

                if lostStreamCount > 0 {
                    Text("·")
                    Text("\(lostStreamCount) lost")
                }
            }
            .font(.caption.monospacedDigit())
            .fontDesign(.monospaced)
            .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6), in: Capsule())
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
        ZStack {
            if let displayLayer {
                SampleBufferVideoView(layer: displayLayer)
            } else {
                Color.black
                ProgressView()
                    .tint(.white)
            }

            Text(isLocal ? "\(peerName.uppercased()) — YOU" : peerName.uppercased())
                .font(.caption)
                .fontDesign(.monospaced)
                .fontWeight(.medium)
                .tracking(1)
                .foregroundStyle(.secondary)

            if isDisconnected {
                Color.black.opacity(0.6)
                VStack(spacing: 10) {
                    Circle()
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    Text("Disconnected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .overlay {
            Rectangle()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
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
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            rowDivider

            ForEach(Array(allFeedIDs.enumerated()), id: \.element) { index, feedID in
                CameraRow(
                    feedID: feedID,
                    isHidden: layoutManager.hiddenFeeds.contains(feedID),
                    canSwitchCamera: feedID == .director && canSwitchDirectorCamera,
                    onSwitchCamera: onSwitchDirectorCamera,
                    onToggleHidden: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if layoutManager.hiddenFeeds.contains(feedID) {
                                layoutManager.hiddenFeeds.remove(feedID)
                            } else {
                                layoutManager.hiddenFeeds.insert(feedID)
                            }
                        }
                    }
                )

                if index < allFeedIDs.count - 1 {
                    rowDivider
                }
            }
        }
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color(white: 0.07))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
    }
}

// MARK: - Camera Row

private struct CameraRow: View {
    let feedID: FeedID
    let isHidden: Bool
    var canSwitchCamera = false
    var onSwitchCamera: (() -> Void)?
    var onToggleHidden: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleHidden) {
                Text(feedID.displayName)
                    .font(.body)
                    .foregroundStyle(isHidden ? .white.opacity(0.35) : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canSwitchCamera {
                Button {
                    onSwitchCamera?()
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch camera")
            }

            Button(action: onToggleHidden) {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHidden ? .white.opacity(0.25) : .white.opacity(0.6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack {
        DirectorView()
            .environment(ConnectivityManager())
    }
}
