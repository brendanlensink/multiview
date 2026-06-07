import SwiftUI

struct CameraView: View {
    var body: some View {
        Text("Camera")
            .font(.largeTitle)
            .navigationTitle("Camera")
    }
}

#Preview {
    NavigationStack {
        CameraView()
    }
}
