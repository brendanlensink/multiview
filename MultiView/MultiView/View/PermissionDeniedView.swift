import SwiftUI
import UIKit
import AVFoundation

struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

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
                    Text("Coverage Can't Run")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Required permissions are turned off. Enable them in Settings to use the app.")
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

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Padding.m)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
