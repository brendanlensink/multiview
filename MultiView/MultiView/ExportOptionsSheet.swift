import SwiftUI

struct ExportOptionsSheet: View {
    let session: RecordingSession
    let onDismiss: () -> Void

    @State private var phase: ExportPhase = .choosingOption

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerInfo

                switch phase {
                case .choosingOption:
                    optionButtons
                case .exporting(let status, let progress):
                    exportProgressView(status: status, progress: progress)
                case .success:
                    exportSuccessView
                case .failed(let message):
                    exportFailedView(message: message)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .failed = phase {
                        Button("Done") { onDismiss() }
                    } else if case .success = phase {
                        EmptyView()
                    } else {
                        Button("Cancel") { onDismiss() }
                            .disabled(phase.isExporting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase.isExporting)
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

    private var optionButtons: some View {
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

            Button {
                exportGridComposite()
            } label: {
                ExportOptionRow(
                    title: "Save as grid composite",
                    subtitle: "Combined split-screen video",
                    systemImage: "square.grid.2x2"
                )
            }
        }
    }

    private func exportProgressView(status: String, progress: Double) -> some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(value: progress)
                .tint(.blue)

            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var exportSuccessView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Saved to Photos")
                .font(.headline)

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onDismiss()
            }
        }
    }

    private func exportFailedView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Export Failed")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }

    private func exportSeparateFiles() {
        phase = .exporting(status: "Preparing…", progress: 0)
        Task {
            do {
                try await PhotosExporter.exportSession(session) { @Sendable completed, total in
                    let fraction = Double(completed) / Double(max(total, 1))
                    let status = "Saving file \(completed + 1) of \(total)…"
                    Task { @MainActor in
                        phase = .exporting(status: status, progress: fraction)
                    }
                }
                phase = .success
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func exportGridComposite() {
        phase = .exporting(status: "Compositing grid…", progress: 0)
        Task {
            do {
                let compositeURL = try await GridCompositor.composite(session) { @Sendable progress in
                    Task { @MainActor in
                        phase = .exporting(
                            status: "Compositing grid…",
                            progress: Double(progress) * 0.9
                        )
                    }
                }
                phase = .exporting(status: "Saving to Photos…", progress: 0.95)
                try await PhotosExporter.saveVideoToPhotos(compositeURL)
                RecordingStore.deleteSession(session)
                phase = .success
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

private enum ExportPhase: Equatable {
    case choosingOption
    case exporting(status: String, progress: Double)
    case success
    case failed(String)

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
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
