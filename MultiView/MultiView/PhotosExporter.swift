import Foundation
import Photos
import os

struct PhotosExporter {
    private static let logger = Logger(subsystem: "com.multiview", category: "PhotosExporter")

    enum ExportError: LocalizedError {
        case accessDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Photo library access was denied. Grant access in Settings to save recordings."
            case .saveFailed(let detail):
                "Failed to save video: \(detail)"
            }
        }
    }

    static func exportSeparateFiles(session: RecordingSession) async throws {
        try await requestAccess()

        var errors: [String] = []
        for stream in session.streams {
            let url = RecordingStore.fileURL(for: stream, in: session)
            guard FileManager.default.fileExists(atPath: url.path) else {
                errors.append("\(stream.label): file not found")
                continue
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
                }
                logger.info("Saved \(stream.label) to Photos")
            } catch {
                errors.append("\(stream.label): \(error.localizedDescription)")
                logger.error("Failed to save \(stream.label): \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            throw ExportError.saveFailed(errors.joined(separator: "; "))
        }

        RecordingStore.deleteSession(session)
        logger.info("Export complete, cleaned up temp files for session \(session.id)")
    }

    private static func requestAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.accessDenied
        }
    }
}
