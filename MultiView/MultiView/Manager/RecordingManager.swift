import AVFoundation
import MultipeerConnectivity
import os
import SwiftUI
import UIKit

@MainActor @Observable
final class RecordingManager {
    private let logger = Logger(subsystem: "com.multiview", category: "Recording")

    private(set) var isRecording = false
    private(set) var lostStreamCount = 0
    private let activeRecorders = ActiveRecorders()
    private var sessionStartTime: CMTime = .zero
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private var currentSessionID: String?
    private var currentSessionDir: URL?
    private var currentStartDate: Date?
    private var currentStreamInfos: [RecordingSession.StreamInfo] = []

    private static let localStreamID = "director"

    func startRecording(localPeerName: String, remotePeers: [MCPeerID]) {
        guard !isRecording else { return }

        let sessionID = UUID().uuidString
        let sessionDir = RecordingStore.recordingsDirectory
            .appendingPathComponent(sessionID, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create recording directory: \(error.localizedDescription)")
            return
        }

        FileManager.default.createFile(
            atPath: sessionDir.appendingPathComponent(RecordingSession.inProgressFileName).path,
            contents: nil
        )

        currentSessionID = sessionID
        currentSessionDir = sessionDir
        currentStartDate = Date()
        currentStreamInfos = []

        sessionStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        lostStreamCount = 0
        logger.info("Recording session \(sessionID) starting at \(self.sessionStartTime.seconds)s")

        let localFileName = "\(Self.sanitize(localPeerName)).mov"
        do {
            let localURL = sessionDir.appendingPathComponent(localFileName)
            let localRecorder = try StreamRecorder(
                streamName: localPeerName,
                outputURL: localURL,
                isPassthrough: false,
                includeAudio: true,
                sessionStartTime: sessionStartTime
            )
            activeRecorders.set(localRecorder, for: Self.localStreamID)
            currentStreamInfos.append(RecordingSession.StreamInfo(
                label: localPeerName, fileName: localFileName, isLocal: true, hasAudio: true
            ))
        } catch {
            logger.error("Failed to create local stream recorder: \(error.localizedDescription)")
        }

        for peer in remotePeers {
            let streamID = peer.displayName
            let fileName = "\(Self.sanitize(streamID)).mov"
            let url = sessionDir.appendingPathComponent(fileName)
            do {
                let recorder = try StreamRecorder(
                    streamName: streamID,
                    outputURL: url,
                    isPassthrough: true,
                    includeAudio: false,
                    sessionStartTime: sessionStartTime
                )
                activeRecorders.set(recorder, for: streamID)
                currentStreamInfos.append(RecordingSession.StreamInfo(
                    label: streamID, fileName: fileName, isLocal: false, hasAudio: false
                ))
            } catch {
                logger.error("Failed to create recorder for peer '\(streamID)': \(error.localizedDescription)")
            }
        }

        isRecording = true
        logger.info("Recording started with \(self.activeRecorders.count) streams")
    }

    func stopRecording() async -> RecordingSession? {
        guard isRecording else { return nil }
        isRecording = false
        lostStreamCount = 0

        var stopTaskID: UIBackgroundTaskIdentifier = .invalid
        stopTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.logger.warning("Background task expired before stop-recording finalization completed")
            guard stopTaskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(stopTaskID)
            stopTaskID = .invalid
        }
        defer {
            if stopTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(stopTaskID)
                stopTaskID = .invalid
            }
        }

        let recorders = activeRecorders.removeAll()

        var successCount = 0
        for recorder in recorders {
            if await recorder.finish() != nil {
                successCount += 1
            }
        }

        let session = writeSessionMetadata()
        logger.info("Recording stopped, \(successCount) files saved")
        return session
    }

    func finalizePeerStream(_ peer: MCPeerID) {
        guard isRecording else { return }
        let streamID = peer.displayName
        guard let recorder = activeRecorders.remove(for: streamID) else { return }

        lostStreamCount += 1
        logger.info("Finalizing disconnected peer stream '\(streamID)'")

        Task.detached {
            if let url = await recorder.finish() {
                Logger(subsystem: "com.multiview", category: "Recording")
                    .info("Saved partial recording for '\(streamID)' at \(url.lastPathComponent)")
            }
        }
    }

    func finalizeLocalStream() {
        guard isRecording else { return }
        guard let recorder = activeRecorders.remove(for: Self.localStreamID) else { return }

        lostStreamCount += 1
        logger.info("Finalizing local stream due to capture interruption")

        Task.detached {
            _ = await recorder.finish()
        }
    }

    func finalizeAllForBackground() {
        guard isRecording else { return }

        let app = UIApplication.shared
        backgroundTaskID = app.beginBackgroundTask { [weak self] in
            self?.logger.warning("Background task expired before recording finalization completed")
            self?.endBackgroundTask()
        }

        isRecording = false
        let recorders = activeRecorders.removeAll()
        logger.info("Finalizing \(recorders.count) streams for app backgrounding")

        writeSessionMetadata()

        Task.detached { [weak self] in
            for recorder in recorders {
                _ = await recorder.finish()
            }
            await MainActor.run {
                self?.lostStreamCount = 0
                self?.endBackgroundTask()
            }
        }
    }

    nonisolated func appendLocalSample(_ sampleBuffer: CMSampleBuffer) {
        activeRecorders.recorder(for: "director")?.appendVideo(sampleBuffer)
    }

    nonisolated func appendLocalAudio(_ sampleBuffer: CMSampleBuffer) {
        activeRecorders.recorder(for: "director")?.appendAudio(sampleBuffer)
    }

    nonisolated func appendPeerSample(_ sampleBuffer: CMSampleBuffer, from peer: MCPeerID) {
        activeRecorders.recorder(for: peer.displayName)?.appendVideo(sampleBuffer)
    }

    // MARK: - Private

    @discardableResult
    private func writeSessionMetadata() -> RecordingSession? {
        guard let sessionID = currentSessionID,
              let sessionDir = currentSessionDir,
              let startDate = currentStartDate else { return nil }

        let endDate = Date()
        let session = RecordingSession(
            id: sessionID,
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            streams: currentStreamInfos
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(session)
            try data.write(to: sessionDir.appendingPathComponent(RecordingSession.metadataFileName))
            try? FileManager.default.removeItem(
                at: sessionDir.appendingPathComponent(RecordingSession.inProgressFileName)
            )
            logger.info("Wrote session metadata for \(sessionID)")
        } catch {
            logger.error("Failed to write session metadata: \(error.localizedDescription)")
        }

        currentSessionID = nil
        currentSessionDir = nil
        currentStartDate = nil
        currentStreamInfos = []

        return session
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        logger.info("Background finalization complete")
    }

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

    func remove(for key: String) -> StreamRecorder? {
        lock.withLock { storage.removeValue(forKey: key) }
    }

    func removeAll() -> [StreamRecorder] {
        lock.withLock {
            let values = Array(storage.values)
            storage.removeAll()
            return values
        }
    }
}
