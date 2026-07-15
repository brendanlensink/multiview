import SwiftUI
import UIKit

enum Role: Hashable {
    case director
    case camera
}

struct ContentView: View {
    @State private var selectedRole: Role?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                Spacer()

                AppIconView()
                    .frame(width: 56, height: 56)
                    .padding(.bottom, 16)

                Text("COVERAGE")
                    .font(.title2)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                    .tracking(2)

                Spacer()
                Spacer()
                Spacer()

                Text("CHOOSE YOUR ROLE")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)

                RoleRow(
                    title: "Director",
                    subtitle: "View and record all camera feeds"
                ) {
                    selectedRole = .director
                }
                .padding(.bottom, 20)

                RoleRow(
                    title: "Camera",
                    subtitle: "Stream your feed to a director"
                ) {
                    selectedRole = .camera
                }

                Spacer()

                NavigationLink("Settings") {
                    SettingsView()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.Padding.m)
            }
            .padding(.horizontal, Theme.Padding.xl)
            .navigationDestination(item: $selectedRole) { role in
                switch role {
                case .director:
                    DirectorView()
                case .camera:
                    CameraView()
                }
            }
        }
    }
}

private struct RoleRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AppIconView: View {
    private var uiImage: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }
        return UIImage(named: iconName)
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
