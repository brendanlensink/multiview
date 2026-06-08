import AVFoundation
import MultipeerConnectivity
import os
import SwiftUI

@MainActor @Observable
final class RecordingManager {
    private let logger = Logger(subsystem: "com.multiview", category: "Recording")

    private(set) var isRecording = false
    private let activeRecorders = ActiveRecorders()
    private var sessionStartTime: CMTime = .zero

    private static let localStreamID = "director"

    func startRecording(localPeerName: String, remotePeers: [MCPeerID]) {
        guard !isRecording else { return }

        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create recording directory: \(error.localizedDescription)")
            return
        }

        sessionStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        logger.info("Recording session starting at \(self.sessionStartTime.seconds)s")

        do {
            let localURL = sessionDir.appendingPathComponent("\(Self.sanitize(localPeerName)).mov")
            let localRecorder = try StreamRecorder(
                streamName: localPeerName,
                outputURL: localURL,
                isPassthrough: false,
                sessionStartTime: sessionStartTime
            )
            activeRecorders.set(localRecorder, for: Self.localStreamID)
        } catch {
            logger.error("Failed to create local stream recorder: \(error.localizedDescription)")
        }

        for peer in remotePeers {
            let streamID = peer.displayName
            let url = sessionDir.appendingPathComponent("\(Self.sanitize(streamID)).mov")
            do {
                let recorder = try StreamRecorder(
                    streamName: streamID,
                    outputURL: url,
                    isPassthrough: true,
                    sessionStartTime: sessionStartTime
                )
                activeRecorders.set(recorder, for: streamID)
            } catch {
                logger.error("Failed to create recorder for peer '\(streamID)': \(error.localizedDescription)")
            }
        }

        isRecording = true
        logger.info("Recording started with \(self.activeRecorders.count) streams")
    }

    func stopRecording() async -> [URL] {
        guard isRecording else { return [] }
        isRecording = false

        let recorders = activeRecorders.removeAll()

        var outputURLs: [URL] = []
        for recorder in recorders {
            if let url = await recorder.finish() {
                outputURLs.append(url)
            }
        }

        logger.info("Recording stopped, \(outputURLs.count) files saved")
        return outputURLs
    }

    nonisolated func appendLocalSample(_ sampleBuffer: CMSampleBuffer) {
        activeRecorders.recorder(for: "director")?.append(sampleBuffer)
    }

    nonisolated func appendPeerSample(_ sampleBuffer: CMSampleBuffer, from peer: MCPeerID) {
        activeRecorders.recorder(for: peer.displayName)?.append(sampleBuffer)
    }

    // MARK: - Private

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
    }
}

// MARK: - Thread-Safe Recorder Storage

private final class ActiveRecorders: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storage: [String: StreamRecorder] = [:]

    var count: Int {
        lock.withLock { storage.count }
    }

    func set(_ recorder: StreamRecorder, for key: String) {
        lock.withLock { storage[key] = recorder }
    }

    func recorder(for key: String) -> StreamRecorder? {
        lock.withLock { storage[key] }
    }

    func removeAll() -> [StreamRecorder] {
        lock.withLock {
            let values = Array(storage.values)
            storage.removeAll()
            return values
        }
    }
}
