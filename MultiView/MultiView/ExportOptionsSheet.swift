import SwiftUI

struct ExportOptionsSheet: View {
    let session: RecordingSession
    let onDismiss: () -> Void

    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerInfo

                VStack(spacing: 12) {
                    Button {
                        exportSeparateFiles()
                    } label: {
                        ExportOptionRow(
                            title: "Save as separate files",
                            subtitle: "\(session.streams.count) videos to Photos",
                            systemImage: "square.and.arrow.down.on.square"
                        )
                    }
                    .disabled(isExporting)

                    ExportOptionRow(
                        title: "Save as grid composite",
                        subtitle: "Coming soon",
                        systemImage: "square.grid.2x2"
                    )
                    .opacity(0.4)
                }

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .disabled(isExporting)
                }
            }
            .overlay {
                if isExporting {
                    ProgressView("Saving to Photos...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var headerInfo: some View {
        VStack(spacing: 4) {
            Text(session.startDate, format: .dateTime.month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Duration.seconds(session.duration), format: .time(pattern: .minuteSecond))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func exportSeparateFiles() {
        isExporting = true
        exportError = nil
        Task {
            do {
                try await PhotosExporter.exportSession(session)
                onDismiss()
            } catch {
                exportError = error.localizedDescription
                isExporting = false
            }
        }
    }
}

private struct ExportOptionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
