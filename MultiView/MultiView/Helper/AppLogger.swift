import Foundation
import XCGLogger

enum AppLogger {
    nonisolated(unsafe) static let shared: XCGLogger = {
        let log = XCGLogger(identifier: "com.multiview", includeDefaultDestinations: false)
        let console = ConsoleDestination(identifier: "com.multiview.console")
        console.outputLevel = .debug
        console.showFunctionName = false
        console.showFileName = false
        console.showLineNumber = false
        log.add(destination: console)
        return log
    }()

    static func make(category: String) -> CategoryLogger {
        CategoryLogger(category: category)
    }

    @MainActor
    static func setAdvancedLoggingEnabled(_ enabled: Bool) {
        if enabled {
            guard shared.destination(withIdentifier: LogStore.destinationIdentifier) == nil else { return }
            shared.add(destination: LogStore.shared.makeDestination())
        } else {
            shared.remove(destinationWithIdentifier: LogStore.destinationIdentifier)
            LogStore.shared.clear()
        }
    }
}

/// Thin, Sendable wrapper so call sites can hold a stored `let logger` the same way they did with `os.Logger`,
/// even from `nonisolated`/`@unchecked Sendable` contexts, without exposing XCGLogger's non-Sendable instance.
struct CategoryLogger: Sendable {
    let category: String

    func debug(_ message: @autoclosure () -> Any, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line) {
        AppLogger.shared.debug(tagged(message()), functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }

    func info(_ message: @autoclosure () -> Any, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line) {
        AppLogger.shared.info(tagged(message()), functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }

    func warning(_ message: @autoclosure () -> Any, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line) {
        AppLogger.shared.warning(tagged(message()), functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }

    func error(_ message: @autoclosure () -> Any, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line) {
        AppLogger.shared.error(tagged(message()), functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }

    private func tagged(_ message: Any) -> String {
        "[\(category)] \(message)"
    }
}
