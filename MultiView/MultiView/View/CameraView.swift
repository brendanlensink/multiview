import SwiftUI

struct CameraView: View {
    @Environment(ConnectivityManager.self) private var connectivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var captureManager = CaptureManager()
    @State private var conditionManager = DeviceConditionManager()

    var body: some View {
        cameraContent
        .navigationTitle("Camera")
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                connectivity.handleAppForegrounded()
            } else if scenePhase == .background {
                connectivity.handleAppBackgrounded()
            }
        }
    }

    private var cameraContent: some View {
        ZStack {
            CameraPreviewView(session: captureManager.previewSource)
                .ignoresSafeArea()

            VStack {
                ThrottleIndicator(tier: conditionManager.qualityTier)
                    .padding(.top, 8)
                    .animation(.easeInOut, value: conditionManager.qualityTier)
                Spacer()
                connectionOverlay
                    .padding()
            }
        }
        .onAppear {
            let sender = FrameSender { [connectivity] packet, mode in
                connectivity.sendFrame(packet, mode: mode)
            }
            captureManager.onEncodedFrame = { packet in
                sender.enqueue(packet)
            }
            captureManager.start()
            conditionManager.startMonitoring()
            connectivity.startBrowsing()
        }
        .onDisappear {
            captureManager.onEncodedFrame = nil
            captureManager.stop()
            conditionManager.stopMonitoring()
            connectivity.stopBrowsing()
        }
        .onChange(of: conditionManager.qualityTier) {
            captureManager.applyQualityTier(conditionManager.qualityTier)
        }
        .onChange(of: connectivity.connectionState) {
            if connectivity.connectionState == .connected {
                connectivity.stopBrowsing()
            }
        }
    }

    @ViewBuilder
    private var connectionOverlay: some View {
        switch connectivity.connectionState {
        case .connected:
            if let director = connectivity.connectedPeers.first {
                Label("Connected to \(director.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                Text("Connecting…")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        case .disconnected:
            VStack(spacing: 8) {
                Label("Disconnected", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Reconnecting automatically…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reconnect Now") {
                    connectivity.startBrowsing()
                }
                .font(.subheadline)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        default:
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
