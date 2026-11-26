import SwiftUI

@main
struct EACVisionApp: App {
    @StateObject private var store = NvrStore()
    @AppStorage("eac-local-mode") private var localMode = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { localMode = false; store.handleDeepLink($0) }
        }
    }
}

enum AppTab: Hashable {
    case live
    case recordings
    case events
    case settings
}

struct RootView: View {
    @EnvironmentObject private var store: NvrStore
    @AppStorage("eac-local-mode") private var localMode = false

    var body: some View {
        Group {
            if localMode {
                NavigationStack { LocalCamerasView() }
            } else if store.connected {
                TabView(selection: $store.selectedTab) {
                    NavigationStack { CamerasView() }
                        .tabItem { Label("Live", systemImage: "square.grid.2x2.fill") }
                        .tag(AppTab.live)
                    NavigationStack { RecordingsView() }
                        .tabItem { Label("Registrazioni", systemImage: "clock.arrow.circlepath") }
                        .tag(AppTab.recordings)
                    NavigationStack { EventsView() }
                        .tabItem { Label("Eventi", systemImage: "sparkles") }
                        .tag(AppTab.events)
                    NavigationStack { ConnectionView() }
                        .tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
                        .tag(AppTab.settings)
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .task { if store.connected { await store.refreshCameras() } }
    }
}
