import SwiftUI
import AVFoundation

struct PermissionDeniedView: View {
    let cameraStatus: AVAuthorizationStatus
    let microphoneStatus: AVAuthorizationStatus

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()

            VStack(spacing: Theme.Padding.l) {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    .frame(width: 56, height: 56)

                VStack(spacing: 12) {
                    Text("Coverage Needs Access")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Coverage captures video and audio, so it needs the permissions below. You can turn them on for Coverage anytime in the Settings app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    if cameraStatus == .denied || cameraStatus == .restricted {
                        PermissionRow(title: "Camera", status: cameraStatus)
                    }
                    if microphoneStatus == .denied || microphoneStatus == .restricted {
                        PermissionRow(title: "Microphone", status: microphoneStatus)
                    }
                }
                .overlay(Divider(), alignment: .top)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Theme.Padding.xl)
    }
}

private struct PermissionRow: View {
    let title: String
    let status: AVAuthorizationStatus

    var body: some View {
        HStack {
            Text(title)
                .font(.body)

            Spacer()

            Text(status == .restricted ? "Restricted" : "Denied")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
        .padding(.vertical, Theme.Padding.m)
        .overlay(Divider(), alignment: .bottom)
    }
}

#Preview {
    PermissionDeniedView(cameraStatus: .denied, microphoneStatus: .denied)
}
