//
//  OnboardingStepView.swift
//  Coverage
//
//  Created by Brendan Lensink on 2026-06-08.
//

import SwiftUI

struct OnboardingStepView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(ConnectivityManager.self) private var connectivity

    let step: OnboardingStep
    @State private var isRequesting = false

    private var content: OnboardingStepContent {
        switch step {
        case .camera:
            OnboardingStepContent(
                icon: "camera",
                title: "Camera Access",
                message: "Coverage uses your camera to capture video from this device. Allow camera access so you can stream and record.",
                buttonTitle: "Allow Camera Access"
            )
        case .microphone:
            OnboardingStepContent(
                icon: "mic",
                title: "Microphone Access",
                message: "Coverage uses your microphone to record audio on the director device. Allow microphone access so recordings include sound.",
                buttonTitle: "Allow Microphone Access"
            )
        case .localNetwork:
            OnboardingStepContent(
                icon: "wifi",
                title: "Local Network Access",
                message: "Coverage connects devices over your local network for multi-angle capture. Allow local network access so directors and cameras can find each other.",
                buttonTitle: "Allow Local Network Access"
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Padding.xl)

            Text("STEP \(step.rawValue + 1) OF \(OnboardingStep.allCases.count)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .tracking(1)

            Spacer()

            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: content.icon)
                        .font(.title2)
                        .foregroundStyle(.primary)
                }

            Spacer()

            VStack(spacing: 12) {
                Text(content.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(content.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Padding.l)
            }

            Spacer()
            Spacer()

            Button {
                Task { await requestPermission() }
            } label: {
                Text(content.buttonTitle)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Padding.m)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isRequesting)
            .padding(.bottom, Theme.Padding.m)

            onboardingProgress

            Spacer(minLength: Theme.Padding.l)
        }
        .padding(.horizontal, Theme.Padding.xl)
    }

    private var onboardingProgress: some View {
        HStack(spacing: Theme.Padding.s) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { onboardingStep in
                Circle()
                    .fill(onboardingStep == step ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }

        switch step {
        case .camera:
            await permissionManager.requestCameraAccess()
        case .microphone:
            await permissionManager.requestMicrophoneAccess()
        case .localNetwork:
            connectivity.probeLocalNetworkAccess()
            permissionManager.acknowledgeLocalNetworkAccess()
        }
    }
}
