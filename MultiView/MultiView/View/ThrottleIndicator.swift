import SwiftUI

struct ThrottleIndicator: View {
    let tier: CaptureQualityTier

    var body: some View {
        if let message = tier.statusMessage {
            HStack(spacing: 6) {
                Image(systemName: tier == .minimal ? "flame.fill" : "thermometer.medium")
                    .foregroundStyle(tier == .minimal ? .red : .orange)
                Text(message)
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
