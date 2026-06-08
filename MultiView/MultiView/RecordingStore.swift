import Foundation
import os

struct RecordingStore {
    private static let logger = Logger(subsystem: "com.multiview", category: "RecordingStore")

    static let recordingsDirectory: URL = {
        FileManager.default.temporaryDirectory.appendingPathComponent("recordings", isDirectory: true)
    }()

    static func completedSessions() -> [RecordingSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return entries.compactMap { dir in
            let metadataURL = dir.appendingPathComponent(RecordingSession.metadataFileName)
            guard let data = try? Data(contentsOf: metadataURL),
                  let session = try? decoder.decode(RecordingSession.self, from: data) else {
                return nil
            }
            return session
        }
        .sorted { $0.startDate > $1.startDate }
    }

    static func directoryURL(for session: RecordingSession) -> URL {
        recordingsDirectory.appendingPathComponent(session.id, isDirectory: true)
    }

    static func fileURL(for stream: RecordingSession.StreamInfo, in session: RecordingSession) -> URL {
        directoryURL(for: session).appendingPathComponent(stream.fileName)
    }

    static func cleanupIncompleteRecordings() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for dir in entries {
            let markerURL = dir.appendingPathComponent(RecordingSession.inProgressFileName)
            let metadataURL = dir.appendingPathComponent(RecordingSession.metadataFileName)
            let hasMarker = fm.fileExists(atPath: markerURL.path)
            let hasMetadata = fm.fileExists(atPath: metadataURL.path)

            if hasMarker || !hasMetadata {
                logger.info("Removing incomplete recording: \(dir.lastPathComponent)")
                try? fm.removeItem(at: dir)
            }
        }
    }

    static func deleteSession(_ session: RecordingSession) {
        let dir = directoryURL(for: session)
        try? FileManager.default.removeItem(at: dir)
        logger.info("Deleted recording session: \(session.id)")
    }
}
