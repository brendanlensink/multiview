import SwiftUI
import UIKit

/// Presents the system share sheet for a blob of log text.
/// Copy uses the plain text directly; Mail and Messages get a `.txt` file attachment instead.
struct LogsShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = LogsActivityItemSource(text: text)
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class LogsActivityItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let fileURL: URL?

    init(text: String) {
        self.text = text
        self.fileURL = LogsActivityItemSource.writeTempFile(text: text)
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        switch activityType {
        case .mail, .message:
            return fileURL ?? text
        default:
            return text
        }
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "MultiView Logs"
    }

    private static func writeTempFile(text: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let fileName = "MultiView-Logs-\(formatter.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
