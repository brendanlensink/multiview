import SwiftUI

@main
struct MultiViewApp: App {
    @State private var connectivityManager = ConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectivityManager)
        }
    }
}
