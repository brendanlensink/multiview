import SwiftUI

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSharePresented = false
    private var logStore: LogStore { LogStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Padding.s) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)

                Button {
                    isSharePresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .disabled(logStore.entries.isEmpty)

                Spacer()
            }
            .padding(.top, Theme.Padding.m)
            .padding(.horizontal, Theme.Padding.m)

            Text("Logs")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, Theme.Padding.s)
                .padding(.bottom, Theme.Padding.m)
                .padding(.horizontal, Theme.Padding.m)

            if logStore.entries.isEmpty {
                Spacer()
                Text("No logs recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Padding.xs) {
                            ForEach(logStore.entries) { entry in
                                LogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, Theme.Padding.m)
                        .padding(.bottom, Theme.Padding.l)
                    }
                    .onChange(of: logStore.entries.last?.id) { _, newValue in
                        guard let newValue else { return }
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .sheet(isPresented: $isSharePresented) {
            LogsShareSheet(text: logStore.fullText)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Padding.xs) {
            Text(Self.formatter.string(from: entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(color(for: entry.level))
                .textSelection(.enabled)
        }
    }

    private func color(for level: LogSeverity) -> Color {
        switch level {
        case .error, .severe:
            return .red
        case .warning:
            return .orange
        default:
            return .primary
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        LogsView()
    }
}
