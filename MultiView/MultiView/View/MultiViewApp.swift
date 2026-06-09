import NiceComponents
import SwiftUI

@main
struct MultiViewApp: App {
    @State private var connectivityManager = ConnectivityManager()
    @State private var permissionManager = PermissionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        RecordingStore.cleanupIncompleteRecordings()

        Config.current = Config(
            colorTheme: NiceColorTheme()
                .with(
                    primary: Color.Theme.primary,
                    secondary: Color.Theme.secondary
                )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.isOnboardingComplete {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(connectivityManager)
            .environment(permissionManager)
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    permissionManager.refreshStatuses()
                }
            }.onAppear {
                print(Config.current.primaryButtonStyle.colorStyle.surface)
            }
        }
    }
}
