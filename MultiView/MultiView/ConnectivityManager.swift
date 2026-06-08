import Foundation
import MultipeerConnectivity
import UIKit
import os

enum ConnectionState: Equatable, Sendable {
    case idle
    case advertising
    case browsing
    case connecting
    case connected
    case disconnected
}

private struct SendablePeer: @unchecked Sendable {
    let peer: MCPeerID
}

@MainActor @Observable
final class ConnectivityManager: NSObject {
    private static let serviceType = "multiview"
    private static let peerIDKey = "multiview-peer-id"
    private static let displayNameKey = "multiview-display-name"
    private static let reconnectDelay: TimeInterval = 2

    private nonisolated let logger = Logger(subsystem: "com.multiview", category: "Connectivity")

    private(set) var connectionState: ConnectionState = .idle
    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var discoveredPeers: [MCPeerID] = []

    nonisolated(unsafe) private(set) var peerID: MCPeerID!
    nonisolated(unsafe) private(set) var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var reconnectTask: Task<Void, Never>?
    private var wasAdvertisingBeforeBackground = false
    private var wasBrowsingBeforeBackground = false
    private var isDirector = false

    nonisolated(unsafe) private(set) var timeSync: TimeSyncManager!

    var onFrameReceived: (@Sendable (MCPeerID, FramePacket) -> Void)?

    override init() {
        super.init()
        self.peerID = Self.loadOrCreatePeerID()
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.timeSync = TimeSyncManager { [weak self] data, peer in
            guard let session = self?.session else { return }
            do {
                try session.send(data, toPeers: [peer], with: .reliable)
            } catch {
                self?.logger.error("Failed to send sync message: \(error.localizedDescription)")
            }
        }
        session.delegate = self
    }

    // MARK: - Advertising (Director)

    func startAdvertising() {
        guard advertiser == nil else { return }
        isDirector = true
        reconnectTask?.cancel()
        reconnectTask = nil
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        connectionState = .advertising
        logger.info("Started advertising as \(self.peerID.displayName)")
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        if connectionState == .advertising {
            connectionState = connectedPeers.isEmpty ? .idle : .connected
        }
    }

    // MARK: - Browsing (Camera)

    func startBrowsing() {
        guard browser == nil else { return }
        isDirector = false
        reconnectTask?.cancel()
        reconnectTask = nil
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        connectionState = .browsing
        logger.info("Started browsing for directors")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        discoveredPeers.removeAll()
        if connectionState == .browsing || connectionState == .connecting {
            connectionState = connectedPeers.isEmpty ? .idle : .connected
        }
    }

    // MARK: - Connection

    func invitePeer(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        connectionState = .connecting
        logger.info("Sent invitation to \(peer.displayName)")
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        timeSync.stopAll()
        session.disconnect()
        stopAdvertising()
        stopBrowsing()
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        connectionState = .idle
    }

    // MARK: - Data Sending

    nonisolated func sendFrame(_ packet: FramePacket, mode: FrameSender.SendMode) {
        let data = packet.serialized()
        let reliability: MCSessionSendDataMode = mode == .reliable ? .reliable : .unreliable
        do {
            try session.send(data, toPeers: session.connectedPeers, with: reliability)
        } catch {
            logger.error("Failed to send frame: \(error.localizedDescription)")
        }
    }

    // MARK: - App Lifecycle

    func handleAppBackgrounded() {
        wasAdvertisingBeforeBackground = advertiser != nil
        wasBrowsingBeforeBackground = browser != nil
        reconnectTask?.cancel()
        reconnectTask = nil
        timeSync.stopAll()
        stopAdvertising()
        stopBrowsing()
        logger.info("Suspended connectivity for background")
    }

    func handleAppForegrounded() {
        if wasAdvertisingBeforeBackground {
            startAdvertising()
            wasAdvertisingBeforeBackground = false
        }
        if wasBrowsingBeforeBackground {
            startBrowsing()
            wasBrowsingBeforeBackground = false
        }
        if connectionState == .disconnected {
            scheduleReconnect()
        }
        logger.info("Resumed connectivity for foreground")
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(Self.reconnectDelay))
            guard !Task.isCancelled else { return }
            startBrowsing()
        }
    }

    // MARK: - Peer ID Persistence

    private static func loadOrCreatePeerID() -> MCPeerID {
        let displayName = loadOrCreateDisplayName()

        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let peerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            return peerID
        }

        let peerID = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: peerIDKey)
        }
        return peerID
    }

    private static func loadOrCreateDisplayName() -> String {
        if let name = UserDefaults.standard.string(forKey: displayNameKey), !name.isEmpty {
            return name
        }
        let name = UIDevice.current.name
        UserDefaults.standard.set(name, forKey: displayNameKey)
        return name
    }
}

// MARK: - MCSessionDelegate

extension ConnectivityManager: @preconcurrency MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let wrapper = SendablePeer(peer: peerID)
        Task { @MainActor in
            let peer = wrapper.peer
            switch state {
            case .notConnected:
                self.logger.info("\(peer.displayName) disconnected")
                let wasConnected = self.connectedPeers.contains(peer)
                self.connectedPeers.removeAll { $0 == peer }
                self.timeSync.stopSync(with: peer)
                if self.connectedPeers.isEmpty {
                    if wasConnected {
                        self.connectionState = .disconnected
                        self.scheduleReconnect()
                    } else {
                        self.connectionState = .idle
                    }
                }
            case .connecting:
                self.logger.info("\(peer.displayName) connecting...")
                if self.connectionState == .browsing || self.connectionState == .idle {
                    self.connectionState = .connecting
                }
            case .connected:
                self.logger.info("\(peer.displayName) connected")
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                if !self.connectedPeers.contains(peer) {
                    self.connectedPeers.append(peer)
                }
                self.connectionState = .connected
                if self.isDirector {
                    self.timeSync.startSync(with: peer)
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let typeByte = data.first, let messageType = WireMessageType(rawValue: typeByte) else {
            logger.warning("Received unknown message (\(data.count) bytes) from \(peerID.displayName)")
            return
        }

        let payload = data.dropFirst()

        switch messageType {
        case .frame:
            guard var packet = FramePacket(data: Data(payload)) else {
                logger.warning("Received malformed frame (\(data.count) bytes) from \(peerID.displayName)")
                return
            }
            packet.presentationTime = timeSync.adjustedPresentationTime(packet.presentationTime, from: peerID)
            onFrameReceived?(peerID, packet)

        case .syncPing:
            guard let ping = SyncPing(data: Data(payload)) else {
                logger.warning("Received malformed sync ping from \(peerID.displayName)")
                return
            }
            timeSync.handlePing(ping, from: peerID)

        case .syncPong:
            guard let pong = SyncPong(data: Data(payload)) else {
                logger.warning("Received malformed sync pong from \(peerID.displayName)")
                return
            }
            timeSync.handlePong(pong)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        logger.debug("Received stream '\(streamName)' from \(peerID.displayName)")
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.debug("Started receiving resource '\(resourceName)' from \(peerID.displayName)")
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        logger.debug("Finished receiving resource '\(resourceName)' from \(peerID.displayName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ConnectivityManager: @preconcurrency MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("Received invitation from \(peerID.displayName), accepting")
        invitationHandler(true, session)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        logger.error("Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ConnectivityManager: @preconcurrency MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let wrapper = SendablePeer(peer: peerID)
        Task { @MainActor in
            let peer = wrapper.peer
            self.logger.info("Discovered peer: \(peer.displayName)")
            if !self.discoveredPeers.contains(peer) {
                self.discoveredPeers.append(peer)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let wrapper = SendablePeer(peer: peerID)
        Task { @MainActor in
            let peer = wrapper.peer
            self.logger.info("Lost peer: \(peer.displayName)")
            self.discoveredPeers.removeAll { $0 == peer }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        logger.error("Failed to start browsing: \(error.localizedDescription)")
    }
}
