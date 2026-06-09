import SwiftUI

enum Role: Hashable {
    case director
    case camera
}

struct ContentView: View {
    @State private var selectedRole: Role?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text("MultiView")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    selectedRole = .director
                } label: {
                    Text("Director")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    selectedRole = .camera
                } label: {
                    Text("Camera")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding(.horizontal, 32)
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

#Preview {
    ContentView()
}
