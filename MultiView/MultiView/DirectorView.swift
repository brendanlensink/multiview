import SwiftUI

struct DirectorView: View {
    var body: some View {
        Text("Director")
            .font(.largeTitle)
            .navigationTitle("Director")
    }
}

#Preview {
    NavigationStack {
        DirectorView()
    }
}
