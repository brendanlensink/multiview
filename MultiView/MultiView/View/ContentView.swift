import SwiftUI

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

                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.Theme.primary)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "rectangle.grid.2x2.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 12)

                Text("MultiView")
                    .font(.title)
                    .fontWeight(.medium)
                    .tracking(-0.3)
                    .padding(.bottom, 4)

                Text("Multi-camera recording made simple")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
                Spacer()
                Spacer()

                Text("CHOOSE YOUR ROLE")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)

                RoleCard(
                    title: "Director",
                    subtitle: "View and record all camera feeds",
                    systemImage: "tv",
                    iconColor: .blue
                ) {
                    selectedRole = .director
                }
                .padding(.bottom, 10)

                RoleCard(
                    title: "Camera",
                    subtitle: "Stream your feed to a director",
                    systemImage: "video.fill",
                    iconColor: .green
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

private struct RoleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.title3)
                            .foregroundStyle(iconColor)
                    }

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
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
