import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("captureQualityPreset") private var qualityPreset: String = CaptureQualityPreset.medium.rawValue
    @AppStorage("advancedLoggingEnabled") private var advancedLoggingEnabled: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var selectedPreset: CaptureQualityPreset {
        CaptureQualityPreset(rawValue: qualityPreset) ?? .medium
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .padding(.top, Theme.Padding.m)

                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, Theme.Padding.s)
                    .padding(.bottom, Theme.Padding.l)

                Text("CAPTURE QUALITY")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.bottom, Theme.Padding.s)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(CaptureQualityPreset.allCases) { preset in
                        QualityRow(
                            preset: preset,
                            isSelected: preset == selectedPreset
                        ) {
                            qualityPreset = preset.rawValue
                        }
                        Divider()
                    }
                }
                .padding(.bottom, Theme.Padding.l)

                Text("ADVANCED")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.bottom, Theme.Padding.s)

                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $advancedLoggingEnabled) {
                        Text("Enable advanced logging")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, Theme.Padding.m)
                    .onChange(of: advancedLoggingEnabled) { _, newValue in
                        AppLogger.setAdvancedLoggingEnabled(newValue)
                    }

                    if advancedLoggingEnabled {
                        Divider()
                        NavigationLink {
                            LogsView()
                        } label: {
                            HStack {
                                Text("View Logs")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.Padding.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, Theme.Padding.l)

                Link(destination: URL(string: "https://www.brendanlens.ink/privacypolicy")!) {
                    HStack {
                        Text("Privacy Policy")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Padding.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                    .padding(.bottom, Theme.Padding.l)

                HStack {
                    Text("Version")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(Self.versionString)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Padding.m)
            }
            .padding(.horizontal, Theme.Padding.m)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
    }

    private static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct QualityRow: View {
    let preset: CaptureQualityPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(preset.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Padding.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
