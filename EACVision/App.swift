import SwiftUI

@main
struct EACVisionApp: App {
    @StateObject private var store = NvrStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.20, green: 0.72, blue: 0.94))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: NvrStore

    var body: some View {
        Group {
            if store.connected {
                TabView {
                    NavigationStack { CamerasView() }
                        .tabItem { Label("Telecamere", systemImage: "video") }
                    NavigationStack { RecordingsView() }
                        .tabItem { Label("Registrazioni", systemImage: "clock.arrow.circlepath") }
                    NavigationStack { EventsView() }
                        .tabItem { Label("Eventi AI", systemImage: "sparkles") }
                    NavigationStack { ConnectionView() }
                        .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .task { if store.connected { await store.refreshCameras() } }
    }
}
