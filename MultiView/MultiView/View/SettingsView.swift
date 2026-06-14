import SwiftUI

struct SettingsView: View {
    @AppStorage("captureQualityPreset") private var qualityPreset: String = CaptureQualityPreset.medium.rawValue

    private var selectedPreset: CaptureQualityPreset {
        CaptureQualityPreset(rawValue: qualityPreset) ?? .medium
    }

    var body: some View {
        List {
            Section {
                ForEach(CaptureQualityPreset.allCases) { preset in
                    Button {
                        qualityPreset = preset.rawValue
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if preset == selectedPreset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.Theme.primary)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Capture Quality")
            } footer: {
                Text("Quality may be reduced automatically when the device is warm.")
            }

            Section {
                Link(destination: URL(string: "https://www.brendanlens.ink/privacypolicy")!) {
                    HStack {
                        Text("Privacy Policy")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.versionString)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
