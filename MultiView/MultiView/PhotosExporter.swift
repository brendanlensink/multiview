import Foundation
import os
import Photos

struct PhotosExporter {
    private static let logger = Logger(subsystem: "com.multiview", category: "PhotosExporter")

    enum ExportError: LocalizedError {
        case accessDenied
        case saveFailed(fileCount: Int)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Photo library access was denied. Grant access in Settings to save recordings."
            case .saveFailed(let count):
                "Failed to save \(count) \(count == 1 ? "file" : "files") to the photo library."
            }
        }
    }

    static func exportSession(_ session: RecordingSession) async throws {
        try await requestAccessIfNeeded()

        let sessionDir = RecordingStore.directoryURL(for: session)
        var failCount = 0

        for stream in session.streams {
            let fileURL = sessionDir.appendingPathComponent(stream.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                logger.warning("Recording file missing for stream '\(stream.label)': \(fileURL.lastPathComponent)")
                failCount += 1
                continue
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
                logger.info("Saved '\(stream.label)' to Photos")
            } catch {
                logger.error("Failed to save '\(stream.label)': \(error.localizedDescription)")
                failCount += 1
            }
        }

        if failCount > 0 {
            throw ExportError.saveFailed(fileCount: failCount)
        }

        RecordingStore.deleteSession(session)
        logger.info("Cleaned up session \(session.id) after export")
    }

    private static func requestAccessIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw ExportError.accessDenied
            }
        default:
            throw ExportError.accessDenied
        }
    }
}
