import SwiftUI

@main
struct EACVisionApp: App {
    @StateObject private var store = NvrStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Color(red: 34/255, green: 163/255, blue: 227/255))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var path: [AppPage] = []

    var body: some View {
        Group {
            if store.connected {
                NavigationStack(path: $path) {
                    CamerasView(onNavigate: { path.append($0) })
                        .navigationDestination(for: NvrCamera.self) { CameraDetailView(camera: $0) }
                        .navigationDestination(for: AppPage.self) { page in
                            switch page {
                            case .recordings: RecordingsView()
                            case .events: EventsView()
                            case .settings: ConnectionView()
                            }
                        }
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .task { if store.connected { await store.refreshCameras() } }
    }
}

enum AppPage: Hashable {
    case recordings
    case events
    case settings
}
