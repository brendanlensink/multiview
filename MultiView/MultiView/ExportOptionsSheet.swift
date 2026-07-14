import SwiftUI

struct ExportOptionsSheet: View {
    let session: RecordingSession
    let onDismiss: () -> Void

    @State private var phase: ExportPhase = .choosingOption

    var body: some View {
        Group {
            switch phase {
            case .choosingOption:
                chooseOptionContent
            case .exporting(let status, let progress):
                exportProgressView(status: status, progress: progress)
            case .success:
                exportSuccessView
            case .failed(let message):
                exportFailedView(message: message)
            }
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .interactiveDismissDisabled(phase.isExporting)
    }

    private var chooseOptionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Padding.xs) {
            Text("Export Recording")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("Choose how to save this session to Photos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    exportGridComposite()
                } label: {
                    ExportOptionRow(
                        title: "Grid Composite",
                        subtitle: "One video, all angles arranged side by side"
                    )
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    exportSeparateFiles()
                } label: {
                    ExportOptionRow(
                        title: "Separate Files",
                        subtitle: "Individual clip per camera, synced timestamps"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Theme.Padding.m)

            Button("Cancel") {
                onDismiss()
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Padding.m)
        }
        .padding(.horizontal, Theme.Padding.l)
        .padding(.top, Theme.Padding.l)
        .padding(.bottom, Theme.Padding.m)
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
                .foregroundStyle(.white)

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
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button("Done") {
                onDismiss()
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.bottom, Theme.Padding.m)
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

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Padding.m)
        .contentShape(Rectangle())
    }
}
