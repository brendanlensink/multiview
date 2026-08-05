import Foundation
import Observation
import XCGLogger

enum LogSeverity: String, Sendable {
    case debug, info, warning, error, severe, other

    init(_ level: XCGLogger.Level) {
        switch level {
        case .debug: self = .debug
        case .info: self = .info
        case .warning: self = .warning
        case .error: self = .error
        case .severe: self = .severe
        default: self = .other
        }
    }
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogSeverity
    let text: String
}

/// In-memory ring buffer of recent log lines, populated only while "Enable advanced logging" is on.
/// Backs the Settings > View Logs screen and its share sheet.
@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()
    static let destinationIdentifier = "com.multiview.logstore"

    private static let maxEntries = 2000

    private(set) var entries: [LogEntry] = []

    private init() {}

    var fullText: String {
        entries.map { entry in
            "\(Self.timestampFormatter.string(from: entry.timestamp)) [\(entry.level.rawValue.uppercased())] \(entry.text)"
        }.joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }

    func makeDestination() -> MemoryDestination {
        MemoryDestination(identifier: Self.destinationIdentifier)
    }

    fileprivate func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

final class MemoryDestination: BaseDestination, @unchecked Sendable {
    override init(owner: XCGLogger? = nil, identifier: String = "") {
        super.init(owner: owner, identifier: identifier)
        outputLevel = .debug
        showDate = false
        showLevel = false
        showFileName = false
        showLineNumber = false
        showFunctionName = false
    }

    override func output(logDetails: LogDetails, message: String) {
        let entry = LogEntry(timestamp: logDetails.date, level: LogSeverity(logDetails.level), text: message)
        Task { @MainActor in
            LogStore.shared.append(entry)
        }
    }
}
