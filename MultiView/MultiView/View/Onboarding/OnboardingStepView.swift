//
//  OnboardingStepView.swift
//  MultiView
//
//  Created by Brendan Lensink on 2026-06-08.
//

import NiceComponents
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
                icon: "camera.fill",
                title: "Camera Access",
                message: "MultiView uses your camera to capture video from this device. Allow camera access so you can stream and record.",
                buttonTitle: "Allow Camera Access"
            )
        case .microphone:
            OnboardingStepContent(
                icon: "mic.fill",
                title: "Microphone Access",
                message: "MultiView uses your microphone to record audio on the director device. Allow microphone access so recordings include sound.",
                buttonTitle: "Allow Microphone Access"
            )
        case .localNetwork:
            OnboardingStepContent(
                icon: "wifi",
                title: "Local Network Access",
                message: "MultiView connects devices over your local network for multi-angle capture. Allow local network access so directors and cameras can find each other.",
                buttonTitle: "Allow Local Network Access"
            )
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            NiceText(content.title, style: .screenTitle)
                .multilineTextAlignment(.center)

            Group {
                NiceImage(systemIcon: content.icon, width: 300, height: 150, tintColor: Color.Theme.primary, contentMode: .fit)
            }.frame(height: 350)


            NiceText(content.message, style: .body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Padding.m)

            NiceButton(content.buttonTitle, style: .primary) {
                Task { await requestPermission() }
            }

            onboardingProgress
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    private var onboardingProgress: some View {
        HStack(spacing: Theme.Padding.m) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { onboardingStep in
                Circle()
                    .fill(onboardingStep.rawValue <= step.rawValue ? Color.Theme.primary : Color.Theme.primary.opacity(0.3))
                    .frame(width: 8, height: 8)
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
