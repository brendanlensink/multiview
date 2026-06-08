import Foundation

struct RecordingSession: Codable, Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let streams: [StreamInfo]

    struct StreamInfo: Codable {
        let label: String
        let fileName: String
        let isLocal: Bool
        let hasAudio: Bool
    }

    static let metadataFileName = "session.json"
    static let inProgressFileName = ".recording"
}
