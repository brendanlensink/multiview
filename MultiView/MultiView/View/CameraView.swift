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
                HStack {
                    if connectivity.connectionState == .connected {
                        LiveBadge()
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Padding.m)
                .padding(.top, Theme.Padding.s)

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
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Text("Connected to \(director.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(Theme.Padding.m)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
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
            VStack(spacing: Theme.Padding.s) {
                Text("Disconnected")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Reconnecting automatically…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    connectivity.startBrowsing()
                } label: {
                    Text("Reconnect Now")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Padding.s)
                        .background(Color(red: 1, green: 90 / 255, blue: 54 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, Theme.Padding.xs)
            }
            .padding(Theme.Padding.m)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text("NEARBY DIRECTORS")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.horizontal, Theme.Padding.m)
                    .padding(.top, Theme.Padding.m)
                    .padding(.bottom, Theme.Padding.s)

                if connectivity.discoveredPeers.isEmpty {
                    Text("Looking for directors…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Padding.m)
                        .padding(.bottom, Theme.Padding.m)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(connectivity.discoveredPeers.enumerated()), id: \.element) { index, peer in
                            Button {
                                connectivity.invitePeer(peer)
                            } label: {
                                HStack {
                                    Text(peer.displayName)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, Theme.Padding.m)
                                .padding(.vertical, Theme.Padding.s + 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < connectivity.discoveredPeers.count - 1 {
                                Divider()
                                    .padding(.leading, Theme.Padding.m)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Padding.s)
                }
            }
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Live Badge

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("LIVE")
                .font(.caption)
                .fontWeight(.bold)
                .fontDesign(.monospaced)
                .tracking(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        CameraView()
            .environment(ConnectivityManager())
    }
}
