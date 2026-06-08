import SwiftUI
import UIKit
import AVFoundation

struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    let cameraStatus: AVAuthorizationStatus
    let microphoneStatus: AVAuthorizationStatus

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                if cameraStatus == .denied || cameraStatus == .restricted {
                    PermissionRow(
                        icon: "camera",
                        title: "Camera",
                        status: cameraStatus
                    )
                }
                if microphoneStatus == .denied || microphoneStatus == .restricted {
                    PermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        status: microphoneStatus
                    )
                }
            }

            Text("Open Settings to grant access.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let status: AVAuthorizationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(status == .restricted ? "Restricted" : "Denied")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    PermissionDeniedView(cameraStatus: .denied, microphoneStatus: .denied)
}
