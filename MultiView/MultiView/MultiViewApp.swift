import SwiftUI

@main
struct MultiViewApp: App {
    @State private var connectivityManager = ConnectivityManager()

    init() {
        RecordingStore.cleanupIncompleteRecordings()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectivityManager)
        }
    }
}
