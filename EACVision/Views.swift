import AVKit
import Combine
import Photos
import SwiftUI
import UIKit

struct CamerasView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var openedCamera: NvrCamera?
    @State private var tourRequested = false
    @State private var autoTourStarted = false
    @AppStorage("eac-tour-start") private var startTourOnOpen = false
    @AppStorage("eac-grid-cols") private var gridCols = 2

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.error.isEmpty {
                errorBanner
            }
            if store.cameras.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(store.cameras) { camera in
                            Button {
                                Haptics.tap()
                                tourRequested = false
                                openedCamera = camera
                            } label: {
                                CameraTile(camera: camera, live: (store.cameras.firstIndex(of: camera) ?? 0) < 4)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .padding(10)
                }
                .refreshable { await store.refreshCameras() }
            }
        }
        .background { Theme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { startAutomaticTour() }
        .onChange(of: store.cameras) { _, _ in startAutomaticTour() }
        .fullScreenCover(item: $openedCamera) { camera in
            NavigationStack {
                CameraDetailView(camera: camera, startTour: tourRequested)
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
    }

    private func startAutomaticTour() {
        guard startTourOnOpen, !autoTourStarted, store.cameras.count > 1 else { return }
        autoTourStarted = true
        tourRequested = true
        openedCamera = store.cameras.first
    }

    private var gridColumns: [GridItem] {
        let count = max(1, min(gridCols, max(1, store.cameras.count)))
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("EACLogo").resizable().scaledToFit().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EAC Vision").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Electronic Ascione Company").font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 4)
                headerButton("clock.arrow.circlepath") { store.selectedTab = .recordings }
                headerButton("arrow.clockwise") { Task { await store.refreshCameras() } }
                Menu {
                    Button("Registrazioni", systemImage: "clock.arrow.circlepath") { store.selectedTab = .recordings }
                    Button("Eventi AI", systemImage: "sparkles") { store.selectedTab = .events }
                    Button("Impostazioni", systemImage: "gearshape") { store.selectedTab = .settings }
                } label: { headerIcon("line.3.horizontal") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(store.availableViews) { view in
                            Button(view.name, systemImage: view.id == store.selectedViewId ? "checkmark" : "square.grid.2x2") {
                                store.chooseView(view.id)
                            }
                        }
                    } label: {
                        Chip(title: store.viewName, symbol: "square.grid.2x2")
                    }
                    Menu {
                        ForEach(1...3, id: \.self) { cols in
                            Button(cols == 1 ? "Una camera grande" : "\(cols) colonne",
                                   systemImage: cols == 1 ? "rectangle" : (cols == 2 ? "square.grid.2x2" : "square.grid.3x3")) {
                                gridCols = cols
                            }
                        }
                    } label: {
                        Chip(title: "Griglia \(gridCols)", symbol: "slider.horizontal.3")
                    }
                    Chip(title: store.layoutName, symbol: "rectangle.grid.2x2")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerIcon(symbol) }.buttonStyle(.plain)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white).frame(width: 36, height: 34)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(store.error).font(.footnote).foregroundStyle(.orange)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("EACLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                .shadow(color: Theme.accent.opacity(0.4), radius: 18)
            Text("Nessuna telecamera nella vista").font(.title3.bold())
            Text("Aggiungi le camere con ONVIF in Home Assistant e selezionale nella vista principale.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            Button { store.selectedTab = .settings } label: {
                Label("Apri Impostazioni", systemImage: "gearshape")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(28)
    }
}

private struct CameraTile: View {
    @EnvironmentObject private var store: NvrStore
    let camera: NvrCamera
    let live: Bool
    @State private var player = AVPlayer()
    @State private var snapshotTick = 0
    @State private var streamReady = false
    @State private var streamMode = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            CameraSnapshot(camera: camera, tick: snapshotTick).allowsHitTesting(false)
            if live {
                PlayerSurface(player: player, onReady: { streamReady = $0 })
                    .opacity(streamReady ? 1 : 0.01).allowsHitTesting(false)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                Circle().fill(camera.recording == true ? Color.red : Theme.accent).frame(width: 7, height: 7)
                Text(camera.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
            }
            .shadow(color: .black, radius: 3)
            .padding(9)
            statusBadge
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .onAppear { if live { startStream() } }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            if !streamReady { snapshotTick += 1 }
        }
        .task(id: streamMode) {
            guard live else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, !streamReady, streamMode == 0 else { return }
            streamMode = 1
            startStream()
        }
    }

    private var recordingBadge: Bool { live && streamReady && camera.recording == true }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if recordingBadge {
                Circle().fill(.white).frame(width: 4, height: 4)
            }
            Text(recordingBadge ? "REC" : (live && streamReady ? "LIVE" : "SNAP"))
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(recordingBadge ? Color.red.opacity(0.85) : Theme.accent.opacity(0.75), in: Capsule())
    }

    private func startStream() {
        var query = [URLQueryItem(name: "src", value: camera.id)]
        if streamMode == 1 { query.append(URLQueryItem(name: "mode", value: "ts")) }
        guard let url = store.endpoint("/eacnvr/hls.m3u8", query: query) else { return }
        streamReady = false
        player.isMuted = true
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}

struct CameraDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NvrStore
    let camera: NvrCamera
    @State private var activeId: String
    @State private var touring = false
    @State private var tourCountdown = 10
    @AppStorage("eac-tour-seconds") private var tourSeconds = 10
    @State private var player = AVPlayer()
    @State private var audioOn = false
    @State private var controlsVisible = true
    @State private var streamReady = false
    @State private var streamMode = 0
    @State private var streamAttempt = 0
    @State private var snapshotTick = 0
    @State private var streamMessage = ""
    @State private var controlError = ""
    @State private var showSiren = false
    @State private var showPtzPanel = false
    @State private var ptzStartTask: Task<Void, Never>?
    @State private var zoom = 1.0
    @State private var zoomRequest = 0
    @State private var savingPhoto = false
    @State private var photoMessage = ""
    @State private var shareItem: ShareItem?

    init(camera: NvrCamera, startTour: Bool = false) {
        self.camera = camera
        _activeId = State(initialValue: camera.id)
        _touring = State(initialValue: startTour)
    }

    private var activeCamera: NvrCamera { store.cameras.first(where: { $0.id == activeId }) ?? camera }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraSnapshot(camera: activeCamera, tick: snapshotTick)
                .aspectRatio(16/9, contentMode: .fit)
            ZoomablePlayerSurface(player: player, onReady: { ready in
                streamReady = ready
                if ready { streamMessage = "" }
            }, onTap: { withAnimation { controlsVisible.toggle() } },
               onSwipe: { step in switchCamera(step) },
               onZoom: { value in zoom = Double(value) },
               zoomRequest: zoomRequest, requestedZoom: CGFloat(zoom))
                .aspectRatio(16/9, contentMode: .fit)
                .opacity(streamReady ? 1 : 0.01)
            if controlsVisible {
                VStack {
                    topBar
                    if !streamReady {
                        Text(streamMessage.isEmpty ? "Collegamento al live… Anteprima disponibile." : streamMessage)
                            .font(.caption).foregroundStyle(.white)
                            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 8)
                    } else if streamMode == 1 {
                        Text("Formato H.264 compatibile attivo; l'audio non è disponibile in questo flusso.")
                            .font(.caption).foregroundStyle(.white)
                            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 8)
                    }
                    if !photoMessage.isEmpty {
                        Text(photoMessage).font(.caption).foregroundStyle(.white)
                            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 8)
                    }
                    Spacer()
                    controlsPanel
                }
                .padding(10)
            }
        }
        .confirmationDialog("Sirena EZVIZ", isPresented: $showSiren) {
            Button("Attiva la sirena", role: .destructive) { setSiren(true) }
            Button("Spegni la sirena") { setSiren(false) }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            tourCountdown = tourSeconds
            if touring { controlsVisible = false }
            start()
        }
        .onDisappear { touring = false; player.pause(); player.replaceCurrentItem(with: nil) }
        .onChange(of: activeId) { _, _ in
            zoom = 1
            zoomRequest += 1
            streamMode = 0
            streamMessage = ""
            controlError = ""
            photoMessage = ""
            showPtzPanel = false
            tourCountdown = tourSeconds
            start()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard touring, !controlsVisible, zoom <= 1, store.cameras.count > 1 else { return }
            tourCountdown -= 1
            if tourCountdown <= 0 { switchCamera(1) }
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            if !streamReady { snapshotTick += 1 }
        }
        .task(id: streamAttempt) {
            guard player.currentItem != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, !streamReady else { return }
            if streamMode == 0 {
                streamMode = 1
                start()
            } else {
                streamMessage = "Il live HLS non si apre. Mostro le istantanee; controlla che la camera fornisca H.264/H.265 e aggiorna EAC Vision su HA."
                controlsVisible = true
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline.bold())
                    .frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Torna alla griglia")
            VStack(alignment: .leading, spacing: 3) {
                Text(activeCamera.name).font(.subheadline.bold()).lineLimit(1)
                Text(touring ? "Ronda · ogni \(tourSeconds) secondi" : "Telecamera in diretta")
                    .font(.caption2).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 4)
            Text(touring ? "RONDA" : (activeCamera.recording == true ? "REC" : "LIVE"))
                .font(.caption2.bold()).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(touring ? Color.green.opacity(0.65) : (activeCamera.recording == true ? Color.red.opacity(0.8) : Theme.accent.opacity(0.8)), in: Capsule())
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }

    private var controlsPanel: some View {
        VStack(spacing: 9) {
            if showPtzPanel && activeCamera.ezPtz == true {
                VStack(spacing: 6) {
                    Text("Muovi la telecamera").font(.caption.bold()).foregroundStyle(Theme.dim)
                    ptzButton("Su", symbol: "arrow.up", direction: "up")
                    HStack(spacing: 30) {
                        ptzButton("Sinistra", symbol: "arrow.left", direction: "left")
                        ptzButton("Giù", symbol: "arrow.down", direction: "down")
                        ptzButton("Destra", symbol: "arrow.right", direction: "right")
                    }
                    if !controlError.isEmpty { Text(controlError).font(.caption).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity).padding(9)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
            }
            if zoom > 1.05 {
                Text("Zoom \(zoom.formatted(.number.precision(.fractionLength(1))))× · trascina per esplorare · doppio tocco per adattare")
                    .font(.caption2).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                viewerTile(audioOn ? "Audio acceso" : "Audio", symbol: audioOn ? "speaker.wave.2.fill" : "speaker.slash") {
                    guard streamMode != 1 else { return }
                    audioOn.toggle(); player.isMuted = !audioOn
                }
                viewerTile(savingPhoto ? "Foto…" : "Foto", symbol: "camera.fill") {
                    guard !savingPhoto else { return }
                    Task { await savePhoto() }
                }
                NavigationLink {
                    RecordingsView(inStack: true, initialCameraId: activeCamera.id)
                } label: {
                    viewerTileLabel("Archivio", symbol: "clock.arrow.circlepath")
                }.buttonStyle(.plain)
                if store.cameras.count > 1 {
                    viewerTile(touring ? "Ferma ronda" : "Ronda", symbol: touring ? "stop.fill" : "play.square.stack.fill", active: touring) {
                        touring.toggle(); tourCountdown = tourSeconds
                        if touring { controlsVisible = false; audioOn = false; player.isMuted = true }
                    }
                }
            }
            HStack(spacing: 8) {
                if store.cameras.count > 1 {
                    viewerTile("Precedente", symbol: "chevron.left") { switchCamera(-1) }
                    viewerTile("Successiva", symbol: "chevron.right") { switchCamera(1) }
                }
                if activeCamera.ezPtz == true {
                    viewerTile("PTZ", symbol: "arrow.up.left.and.arrow.down.right", active: showPtzPanel) {
                        showPtzPanel.toggle()
                    }
                }
                Menu {
                    Button("Salva foto in Libreria", systemImage: "square.and.arrow.down") {
                        guard !savingPhoto else { return }
                        Task { await savePhoto() }
                    }
                    Button("Condividi la foto", systemImage: "square.and.arrow.up") {
                        Task { await sharePhoto() }
                    }
                    Button("Ricollega il video", systemImage: "arrow.clockwise") { streamMode = 0; start() }
                    Button("Adatta il video", systemImage: "arrow.down.right.and.arrow.up.left") { zoom = 1; zoomRequest += 1 }
                    if activeCamera.ezSiren == true {
                        Button("Sirena EZVIZ", systemImage: "alarm") { showSiren = true }
                    }
                } label: { viewerTileLabel("Altro", symbol: "ellipsis.circle") }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private func start() {
        var query = [URLQueryItem(name: "src", value: activeCamera.id)]
        if streamMode == 1 { query.append(URLQueryItem(name: "mode", value: "ts")) }
        guard let url = store.endpoint("/eacnvr/hls.m3u8", query: query) else { return }
        streamReady = false
        streamMessage = streamMode == 1 ? "Provo il formato video alternativo…" : ""
        streamAttempt += 1
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = !audioOn
        player.play()
    }

    private func viewerTileLabel(_ title: String, symbol: String, active: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(active ? .white : Theme.dim)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(active ? Theme.accent.opacity(0.28) : Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Theme.accent : Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func viewerTile(_ title: String, symbol: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: { viewerTileLabel(title, symbol: symbol, active: active) }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(title)
    }

    private func ptzButton(_ title: String, symbol: String, direction: String) -> some View {
        PtzPressButton(title: title, symbol: symbol, onStart: {
            let selected = activeCamera
            ptzStartTask = Task {
                do { try await store.ezvizPtz(camera: selected, direction: direction, action: "start"); controlError = "" }
                catch { controlError = error.localizedDescription }
            }
        }, onStop: {
            let selected = activeCamera
            let started = ptzStartTask
            ptzStartTask = nil
            Task {
                await started?.value
                do { try await store.ezvizPtz(camera: selected, direction: direction, action: "stop") }
                catch { controlError = error.localizedDescription }
            }
        })
    }

    private func setSiren(_ enabled: Bool) {
        Task {
            do { try await store.ezvizSiren(camera: activeCamera, enabled: enabled); controlError = "" }
            catch { controlError = error.localizedDescription }
        }
    }

    private func fetchSnapshot() async throws -> UIImage {
        guard let url = store.endpoint("/eacnvr/snapshot", query: [
            URLQueryItem(name: "cam", value: activeCamera.id),
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
        ]) else { throw NvrError(message: "Registratore non collegato") }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw NvrError(message: "Istantanea non disponibile") }
        return image
    }

    private func savePhoto() async {
        savingPhoto = true
        photoMessage = "Scarico la foto…"
        do {
            let image = try await fetchSnapshot()
            saveToPhotos(image)
        } catch {
            photoMessage = error.localizedDescription
            Haptics.warning()
            clearPhotoMessageAfterDelay()
        }
        savingPhoto = false
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    photoMessage = "Foto salvata nella Libreria foto"
                    Haptics.success()
                } else {
                    photoMessage = error?.localizedDescription ?? "Salvataggio non riuscito"
                    Haptics.warning()
                }
                clearPhotoMessageAfterDelay()
            }
        }
    }

    private func sharePhoto() async {
        photoMessage = ""
        do {
            let image = try await fetchSnapshot()
            shareItem = ShareItem(image: image)
        } catch {
            photoMessage = error.localizedDescription
            clearPhotoMessageAfterDelay()
        }
    }

    private func clearPhotoMessageAfterDelay() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            photoMessage = ""
        }
    }

    private func switchCamera(_ step: Int) {
        guard store.cameras.count > 1, let index = store.cameras.firstIndex(where: { $0.id == activeId }) else { return }
        activeId = store.cameras[(index + step + store.cameras.count) % store.cameras.count].id
        tourCountdown = tourSeconds
    }
}

private struct PtzPressButton: View {
    let title: String
    let symbol: String
    let onStart: () -> Void
    let onStop: () -> Void
    @State private var pressing = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 54, height: 48)
            .background(pressing ? Theme.accent.opacity(0.7) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { pressing = true; onStart() } }
                .onEnded { _ in if pressing { pressing = false; onStop() } })
            .onDisappear { if pressing { pressing = false; onStop() } }
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onStart(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: onStop) }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onReady: ((Bool) -> Void)?
    private var readiness: NSKeyValueObservation?

    func watchReadiness() {
        guard readiness == nil else { return }
        readiness = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            DispatchQueue.main.async { self?.onReady?(layer.isReadyForDisplay) }
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var onReady: ((Bool) -> Void)? = nil
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.videoLayer.videoGravity = .resizeAspect
        view.onReady = onReady
        view.watchReadiness()
        return view
    }
    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.onReady = onReady
        if view.videoLayer.player !== player { view.videoLayer.player = player }
    }
}

final class ZoomPlayerView: UIView, UIScrollViewDelegate {
    let scroll = UIScrollView()
    let video = PlayerLayerView()
    var onTap: (() -> Void)?
    var onSwipe: ((Int) -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var resetVersion = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false
        scroll.bouncesZoom = true
        scroll.backgroundColor = .black
        addSubview(scroll)
        video.videoLayer.videoGravity = .resizeAspect
        video.watchReadiness()
        scroll.addSubview(video)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(doubleTap)
        scroll.addGestureRecognizer(singleTap)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(_:)))
            swipe.direction = direction
            scroll.addGestureRecognizer(swipe)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let changed = scroll.bounds.size != bounds.size
        scroll.frame = bounds
        if changed {
            scroll.setZoomScale(1, animated: false)
            video.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { video }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        let value = scrollView.zoomScale
        DispatchQueue.main.async { self.onZoom?(value) }
    }

    @objc private func didTap() { onTap?() }

    @objc private func didDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scroll.zoomScale > 1.05 {
            scroll.setZoomScale(1, animated: true)
        } else {
            let scale: CGFloat = 2.5
            let point = gesture.location(in: video)
            let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                   width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func didSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard scroll.zoomScale <= 1.05 else { return }
        onSwipe?(gesture.direction == .left ? 1 : -1)
    }
}

struct ZoomablePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var onReady: ((Bool) -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onSwipe: ((Int) -> Void)? = nil
    var onZoom: ((CGFloat) -> Void)? = nil
    var zoomRequest = 0
    var requestedZoom: CGFloat = 1

    func makeUIView(context: Context) -> ZoomPlayerView { ZoomPlayerView() }

    func updateUIView(_ view: ZoomPlayerView, context: Context) {
        view.video.onReady = onReady
        if view.video.videoLayer.player !== player { view.video.videoLayer.player = player }
        view.onTap = onTap
        view.onSwipe = onSwipe
        view.onZoom = onZoom
        if view.resetVersion != zoomRequest {
            view.resetVersion = zoomRequest
            view.scroll.setZoomScale(min(6, max(1, requestedZoom)), animated: true)
        }
    }
}

private struct CameraSnapshot: View {
    @EnvironmentObject private var store: NvrStore
    let camera: NvrCamera
    let tick: Int

    var body: some View {
        AsyncImage(url: store.endpoint("/eacnvr/snapshot", query: [
            URLQueryItem(name: "cam", value: camera.id), URLQueryItem(name: "t", value: String(tick))
        ])) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Color.black.overlay {
                Label("Istantanea non disponibile", systemImage: "video.slash")
                    .font(.caption2).foregroundStyle(Theme.dim).padding(8)
            }
            default: Color.black.overlay { ProgressView().tint(Theme.accent) }
            }
        }
    }
}

struct RecordingsView: View {
    let inStack: Bool
    let initialCameraId: String?

    init(inStack: Bool = false, initialCameraId: String? = nil) {
        self.inStack = inStack
        self.initialCameraId = initialCameraId
    }

    @EnvironmentObject private var store: NvrStore
    @State private var cameraId = ""
    @State private var day = ""
    @State private var days: [NvrDay] = []
    @State private var segments: [NvrSegment] = []
    @State private var recordingEvents: [NvrEvent] = []
    @State private var player = AVPlayer()
    @State private var previewPlayer = AVPlayer()
    @State private var activeName = ""
    @State private var previewName = ""
    @State private var seconds = 0.0
    @State private var dragging = false
    @State private var lastPreview = Date.distantPast
    @State private var error = ""
    @State private var audioOn = true
    @State private var zoom = 1.0
    @State private var zoomRequest = 0
    @State private var speed = 1.0
    @State private var playing = false
    @State private var armedJump: RecordingJump?

    private var camera: NvrCamera? { store.allCameras.first { $0.id == cameraId } }
    private var dayStart: Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: day)?.timeIntervalSince1970 ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !inStack { header }
                if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.footnote) }
                Picker("Telecamera", selection: $cameraId) {
                    ForEach(store.allCameras) { camera in Text(camera.name).tag(camera.id) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.day) { item in
                            Button(item.day) { selectDay(item.day) }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(item.day == day ? Theme.accent.opacity(0.35) : Theme.panel2,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.day == day ? Theme.accent : Theme.line))
                        }
                    }
                }
                ZStack {
                    Color.black
                    ZoomablePlayerSurface(player: player, onZoom: { value in zoom = Double(value) },
                                          zoomRequest: zoomRequest, requestedZoom: CGFloat(zoom))
                }
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                    Button(playing ? "Pausa" : "Riprendi", systemImage: playing ? "pause.fill" : "play.fill") {
                        Haptics.tap()
                        if playing { player.pause(); playing = false }
                        else { player.play(); player.rate = Float(speed); playing = true }
                    }
                    Button("−10 s", systemImage: "gobackward.10") { play(at: max(0, seconds - 10)) }
                    Button("+10 s", systemImage: "goforward.10") { play(at: min(86399, seconds + 10)) }
                    Button(audioOn ? "Audio" : "Muto", systemImage: audioOn ? "speaker.wave.2" : "speaker.slash") {
                        audioOn.toggle(); player.isMuted = !audioOn
                    }
                } }.buttonStyle(.bordered).font(.caption).tint(Theme.accentSoft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Velocità \(speed.formatted())×", systemImage: "speedometer") {
                            let speeds = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
                            speed = speeds[(speeds.firstIndex(of: speed).map { $0 + 1 } ?? 1) % speeds.count]
                            if player.rate > 0 { player.rate = Float(speed) }
                        }
                        Button("Zoom −", systemImage: "minus.magnifyingglass") { setZoom(max(1, zoom - 0.5)) }
                        Button("Zoom +", systemImage: "plus.magnifyingglass") { setZoom(min(6, zoom + 0.5)) }
                        Button("Adatta", systemImage: "arrow.down.right.and.arrow.up.left") { setZoom(1) }
                    }.buttonStyle(.bordered).font(.caption).tint(Theme.accentSoft)
                }
                Text(dragging ? "Anteprima · \(clock(seconds))" : "\(day) · \(clock(seconds))")
                    .font(.headline.monospacedDigit())
                PlayerSurface(player: previewPlayer)
                    .frame(height: dragging ? 150 : 0)
                    .clipped()
                    .opacity(dragging ? 1 : 0)
                    .background(.black, in: RoundedRectangle(cornerRadius: 10))
                Slider(value: $seconds, in: 0...86399, onEditingChanged: { editing in
                    dragging = editing
                    if editing { player.pause(); playing = false; showPreview(seconds, force: true) }
                    else { play(at: seconds); previewPlayer.pause() }
                })
                .onChange(of: seconds) { _, value in if dragging { showPreview(value) } }
                .disabled(segments.isEmpty)
                .tint(Theme.accent)
                HStack { Text("00:00"); Spacer(); Text("Trascina per vedere l'anteprima"); Spacer(); Text("24:00") }
                    .font(.caption2).foregroundStyle(Theme.dim)
                Text("Azzurro: video disponibile · Segni colorati: eventi AI").font(.caption).foregroundStyle(Theme.dim)
                coverage
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        eventLegend("Persone", color: .orange)
                        eventLegend("Animali", color: .green)
                        eventLegend("Veicoli", color: .purple)
                        eventLegend("Movimento", color: .gray)
                    }
                }.font(.caption2).foregroundStyle(Theme.dim)
                if !recordingEvents.isEmpty {
                    Text("VAI A UN EVENTO").font(.caption.bold()).foregroundStyle(Theme.dim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recordingEvents) { event in
                                Button {
                                    Haptics.tap()
                                    let at = event.start / 1000 - dayStart
                                    seconds = at
                                    play(at: at)
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(eventColor(event.label)).frame(width: 7, height: 7)
                                        Text("\(event.label.capitalized) \(clock(event.start / 1000 - dayStart))")
                                    }
                                }.buttonStyle(.bordered).font(.caption).tint(Theme.accentSoft)
                            }
                        }
                    }
                }
                if segments.isEmpty {
                    ContentUnavailableView("Nessun video", systemImage: "clock",
                                           description: Text("Scegli una camera e un giorno con registrazioni."))
                }
            }
            .padding(14)
        }
        .background { Theme.background.ignoresSafeArea() }
        .navigationTitle("Registrazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(inStack ? .visible : .hidden, for: .navigationBar)
        .task(id: store.allCameras) {
            if cameraId.isEmpty {
                if let initial = initialCameraId, store.allCameras.contains(where: { $0.id == initial }) {
                    cameraId = initial
                } else if let first = store.allCameras.first {
                    cameraId = first.id
                }
            }
        }
        .onChange(of: cameraId) { _, _ in Task { await loadDays() } }
        .onAppear { applyPendingJump() }
        .onChange(of: store.pendingJump) { _, _ in applyPendingJump() }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard !dragging, let segment = segments.first(where: { $0.name == activeName }),
                  player.currentItem != nil else { return }
            seconds = max(0, min(86399, segment.start - dayStart + player.currentTime().seconds))
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notice in
            guard let ended = notice.object as? AVPlayerItem, ended === player.currentItem,
                  let index = segments.firstIndex(where: { $0.name == activeName }),
                  index + 1 < segments.count else { return }
            playSegment(segments[index + 1], offset: 0)
        }
        .onDisappear { player.pause(); previewPlayer.pause(); playing = false }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("EACLogo").resizable().scaledToFit().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("REGISTRAZIONI").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.accent)
                Text("Archivio video").font(.title2.bold())
            }
            Spacer()
        }
    }

    private var coverage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                ForEach(segments, id: \.name) { segment in
                    let left = CGFloat(max(0, (segment.start - dayStart) / 86400))
                    let width = CGFloat(max(0, min(segment.dur / 86400, Double(1 - left))))
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * width)
                        .offset(x: proxy.size.width * left)
                }
                ForEach(recordingEvents) { event in
                    let position = (event.start / 1000 - dayStart) / 86400
                    if position >= 0 && position < 1 {
                        Capsule().fill(eventColor(event.label)).frame(width: 4, height: 16)
                            .offset(x: proxy.size.width * CGFloat(position))
                    }
                }
            }
        }.frame(height: 16)
    }

    private func eventLegend(_ name: String, color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(name) }
    }

    private func eventColor(_ label: String) -> Color {
        switch label {
        case "persona": return .orange
        case "animale": return .green
        case "veicolo": return .purple
        case "movimento": return .gray
        default: return .gray
        }
    }

    private func clock(_ value: Double) -> String {
        let s = max(0, min(86399, Int(value)))
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    private func setZoom(_ value: Double) {
        zoom = value
        zoomRequest += 1
    }

    private func selectDay(_ value: String) {
        guard value != day else { return }
        Haptics.tap()
        day = value
        Task { await loadSegments() }
    }

    // Salto diretto a un evento aperto dalla schermata Eventi.
    private func applyPendingJump() {
        guard let jump = store.pendingJump else { return }
        store.pendingJump = nil
        guard store.allCameras.contains(where: { $0.id == jump.cameraId }) else { return }
        armedJump = jump
        if cameraId != jump.cameraId {
            cameraId = jump.cameraId
            if day != jump.day { day = jump.day }
        } else if day != jump.day {
            day = jump.day
            Task { await loadSegments() }
        } else if !segments.isEmpty {
            seekToArmedJump()
        }
    }

    private func seekToArmedJump() {
        guard let jump = armedJump else { return }
        armedJump = nil
        let target = max(0, min(86399, jump.at))
        seconds = target
        play(at: target)
    }

    private func segment(at value: Double) -> NvrSegment? {
        let target = dayStart + value
        return segments.first { $0.start <= target && target < $0.start + $0.dur }
            ?? segments.first { $0.start > target } ?? segments.last
    }

    private func play(at value: Double) {
        guard let segment = segment(at: value) else { return }
        let offset = max(0, min(segment.dur - 0.1, dayStart + value - segment.start))
        playSegment(segment, offset: offset)
    }

    private func playSegment(_ segment: NvrSegment, offset: Double) {
        guard let url = store.endpoint(segment.url) else { return }
        if activeName != segment.name {
            activeName = segment.name
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
        player.isMuted = !audioOn
        player.play()
        player.rate = Float(speed)
        playing = true
    }

    private func showPreview(_ value: Double, force: Bool = false) {
        guard force || Date().timeIntervalSince(lastPreview) > 0.2,
              let segment = segment(at: value), let url = store.endpoint(segment.url) else { return }
        lastPreview = Date()
        let offset = max(0, min(segment.dur - 0.1, dayStart + value - segment.start))
        if previewName != segment.name {
            previewName = segment.name
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        previewPlayer.isMuted = true
        previewPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        previewPlayer.play()
    }

    private func loadDays() async {
        guard let camera else { return }
        let selectedCamera = camera.id
        do {
            let loaded = try await store.days(for: camera)
            guard cameraId == selectedCamera else { return }
            days = loaded
            let missingJump = armedJump.map { jump in !days.contains(where: { $0.day == jump.day }) } ?? false
            if missingJump { armedJump = nil }
            if !days.contains(where: { $0.day == day }) {
                day = days.first?.day ?? ""
            }
            if day.isEmpty { segments = []; recordingEvents = []; player.pause(); player.replaceCurrentItem(with: nil) }
            await loadSegments()
            if missingJump && error.isEmpty { error = "La registrazione di questo evento non è più disponibile." }
        } catch { self.error = error.localizedDescription }
    }

    private func loadSegments() async {
        guard let camera, !day.isEmpty else { return }
        let selectedCamera = camera.id, selectedDay = day
        do {
            player.pause()
            setZoom(1)
            playing = false
            player.replaceCurrentItem(with: nil)
            let loaded = try await store.segments(for: camera, day: selectedDay)
            guard cameraId == selectedCamera && day == selectedDay else { return }
            segments = loaded
            segments = segments.filter { $0.live != true && $0.dur > 0 }.sorted { $0.start < $1.start }
            let dayStartMs = dayStart * 1000
            recordingEvents = ((try? await store.events(for: camera, day: selectedDay)) ?? [])
                .filter { $0.cam == camera.id && $0.start >= dayStartMs && $0.start < dayStartMs + 86400000 }
            activeName = ""
            previewName = ""
            if armedJump != nil {
                seekToArmedJump()
            } else if let first = segments.first {
                seconds = max(0, first.start - dayStart)
                play(at: seconds)
            }
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct EventsView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var events: [NvrEvent] = []
    @State private var error = ""
    @State private var filterLabel = ""
    @State private var filterCamera = ""

    var body: some View {
        VStack(spacing: 10) {
            header
            if !error.isEmpty {
                Text(error).foregroundStyle(.orange).font(.footnote)
                    .padding(.horizontal, 14)
            }
            filterRow
            if filtered.isEmpty && error.isEmpty {
                Spacer()
                ContentUnavailableView(events.isEmpty ? "Nessun evento" : "Nessun risultato",
                                       systemImage: events.isEmpty ? "sparkles" : "line.3.horizontal.decrease.circle",
                                       description: Text(events.isEmpty
                                           ? "L'edizione AI mostra qui persone, veicoli e animali rilevati."
                                           : "Prova a togliere i filtri per vedere più eventi."))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { event in
                            eventCard(event)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .refreshable { await refresh() }
            }
        }
        .background { Theme.background.ignoresSafeArea() }
        .navigationTitle("Eventi AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("EACLogo").resizable().scaledToFit().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("EAC VISION AI").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.accent)
                Text("Eventi").font(.title2.bold())
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 36, height: 34)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    private var filtered: [NvrEvent] {
        events.filter { event in
            (filterLabel.isEmpty || event.label == filterLabel)
                && (filterCamera.isEmpty || event.cam == filterCamera)
        }
    }

    private var labelsPresent: [String] {
        var order = ["persona", "animale", "veicolo", "movimento"]
        let extra = Set(events.map(\.label)).subtracting(order)
        order.append(contentsOf: extra.sorted())
        return order.filter { label in events.contains(where: { $0.label == label }) }
    }

    private var eventCameras: [(id: String, name: String)] {
        var seen: Set<String> = []
        var list: [(id: String, name: String)] = []
        for event in events where !seen.contains(event.cam) {
            seen.insert(event.cam)
            list.append((event.cam, event.camName))
        }
        return list
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Tutti", symbol: "square.grid.2x2", selected: filterLabel.isEmpty && filterCamera.isEmpty) {
                    filterLabel = ""
                    filterCamera = ""
                }
                ForEach(labelsPresent, id: \.self) { label in
                    Chip(title: label.capitalized, symbol: labelSymbol(label), selected: filterLabel == label) {
                        filterLabel = filterLabel == label ? "" : label
                    }
                }
                Menu {
                    Button("Tutte le camere", systemImage: filterCamera.isEmpty ? "checkmark" : "video") {
                        filterCamera = ""
                    }
                    ForEach(eventCameras, id: \.id) { camera in
                        Button(camera.name, systemImage: filterCamera == camera.id ? "checkmark" : "video") {
                            filterCamera = camera.id
                        }
                    }
                } label: {
                    Chip(title: filterCamera.isEmpty ? "Camere" : (eventCameras.first { $0.id == filterCamera }?.name ?? "Camere"),
                         symbol: "video.fill",
                         selected: !filterCamera.isEmpty)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
        }
    }

    private func eventCard(_ event: NvrEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: store.endpoint("/eacnvr/event.jpg", query: [URLQueryItem(name: "id", value: event.id)])) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(.black).aspectRatio(16/9, contentMode: .fit)
                        .overlay { ProgressView().tint(Theme.accent) }
                }
                HStack(spacing: 5) {
                    Image(systemName: labelSymbol(event.label)).font(.system(size: 10, weight: .bold))
                    Text(event.label.capitalized).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(eventColor(event.label).opacity(0.9), in: Capsule())
                .padding(8)
                if event.score > 0 {
                    Text("\(Int((event.score * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.camName).font(.subheadline.bold()).lineLimit(1)
                    Text(Date(timeIntervalSince1970: event.start / 1000).formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    if let jump = makeJump(event) {
                        store.pendingJump = jump
                        store.selectedTab = .recordings
                    }
                } label: {
                    Label("Guarda", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.accent.opacity(0.22), in: Capsule())
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.6)))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(12)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func labelSymbol(_ label: String) -> String {
        switch label {
        case "persona": return "person.fill"
        case "animale": return "pawprint.fill"
        case "veicolo": return "car.fill"
        case "movimento": return "waveform"
        default: return "sparkles"
        }
    }

    private func eventColor(_ label: String) -> Color {
        switch label {
        case "persona": return .orange
        case "animale": return .green
        case "veicolo": return .purple
        case "movimento": return .gray
        default: return Theme.accent
        }
    }

    private func makeJump(_ event: NvrEvent) -> RecordingJump? {
        let date = Date(timeIntervalSince1970: event.start / 1000)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let dayOfMonth = components.day else { return nil }
        let day = String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
        let midnight = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        let at = max(0, event.start / 1000 - midnight - 5)
        return RecordingJump(cameraId: event.cam, day: day, at: at, label: event.label)
    }

    private func refresh() async {
        do { events = try await store.events(); error = "" }
        catch { self.error = "Gli eventi AI sono disponibili con EAC Vision AI su mini PC. \(error.localizedDescription)" }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var address = ""
    @State private var key = ""
    @State private var busy = false
    @State private var error = ""
    @State private var confirmDisconnect = false
    @AppStorage("eac-tour-seconds") private var tourSeconds = 10
    @AppStorage("eac-tour-start") private var startTourOnOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                brandHeader
                SectionCard(title: "COLLEGA IL REGISTRATORE", symbol: "antenna.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Indirizzo Home Assistant o Tailscale").font(.subheadline.bold())
                        TextField("Indirizzo del dispositivo HA", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(12).background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                        Text("Codice delle app").font(.subheadline.bold())
                        SecureField("Codice delle app", text: $key)
                            .padding(12).background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                        connectButton
                        if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                        if store.connected {
                            Label("Collegato a \(store.name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            NavigationLink {
                                NotificationsSettingsView()
                            } label: {
                                Label("Notifiche di rilevamento", systemImage: "bell.badge")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                            }
                        }
                    }
                }
                if store.connected {
                    SectionCard(title: "RONDA TELECAMERE", symbol: "play.square.stack") {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper("Cambia camera ogni \(tourSeconds) secondi", value: $tourSeconds, in: 5...120, step: 5)
                            Toggle("Avvia la ronda all'apertura", isOn: $startTourOnOpen)
                        }
                    }
                    SectionCard(title: "FUORI CASA", symbol: "globe") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("In casa puoi inserire l'IP o l'indirizzo normale di Home Assistant, anche con :8123. EAC Vision prova automaticamente la porta 8766 e la 8767.")
                            Text("Tailscale: usa l'IP 100.x.y.z del dispositivo HA e verifica da Safari che http://100.x.y.z:8766/eacnvr/info (o :8767 per AI) si apra.")
                            Text("DuckDNS: usa https://tuodominio.duckdns.org con un proxy HTTPS che inoltra /eacnvr/. L'indirizzo HA sulla porta 8123 non basta.")
                            Text("Il codice si trova in EAC Vision Home Assistant → Impostazioni → PC, TV e telefono.")
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    SectionCard(title: "APP", symbol: "info.circle") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Versione")
                                Spacer()
                                Text(appVersion).foregroundStyle(Theme.dim).monospacedDigit()
                            }
                            HStack {
                                Text("Registratore")
                                Spacer()
                                Text(store.name).foregroundStyle(Theme.dim).lineLimit(1)
                            }
                            Button {
                                confirmDisconnect = true
                            } label: {
                                Label("Disconnetti", systemImage: "wifi.slash")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.5)))
                            }
                            .buttonStyle(PressableButtonStyle())
                            .foregroundStyle(.red)
                        }
                    }
                }
                Text("EAC Vision · Electronic Ascione Company")
                    .font(.caption2).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 6)
            }
            .font(.subheadline)
            .padding(14)
        }
        .background { Theme.background.ignoresSafeArea() }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { address = store.address; key = store.key }
        .confirmationDialog("Disconnettere il registratore?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnetti", role: .destructive) {
                Haptics.warning()
                store.disconnect()
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("EACLogo").resizable().scaledToFit().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("EAC Vision").font(.title2.bold())
                Text("Impostazioni e collegamento").font(.caption).foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private var connectButton: some View {
        Button {
            Haptics.tap()
            Task {
                busy = true
                do {
                    try await store.connect(address: address, key: key)
                    error = ""
                    Haptics.success()
                } catch {
                    self.error = error.localizedDescription
                    Haptics.warning()
                }
                busy = false
            }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "Collegamento…" : "Collega")
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(busy)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "10"
        return "\(version) (\(build))"
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var targets: [String] = []
    @State private var supportedLabels: [String] = []
    @State private var subscriptions: [String: NotifyChoice] = [:]
    @State private var target = ""
    @State private var enabled = false
    @State private var person = true
    @State private var animal = true
    @State private var vehicle = true
    @State private var motion = true
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionCard(title: "AVVISI SUL TELEFONO", symbol: "bell.badge.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EAC Vision invia gli avvisi tramite Home Assistant Companion anche quando EAC Vision è chiusa. Scegli questo iPhone e attiva i tipi di rilevamento disponibili.")
                            .foregroundStyle(Theme.dim)
                        if targets.isEmpty {
                            Text("Nessun dispositivo Companion disponibile. Controlla che l'app Home Assistant sia collegata e abbia il permesso di mostrare notifiche.")
                                .foregroundStyle(.orange)
                        } else {
                            Picker("Dispositivo", selection: $target) {
                                ForEach(targets, id: \.self) { item in
                                    Text(item.replacingOccurrences(of: "notify.mobile_app_", with: "").replacingOccurrences(of: "_", with: " ")).tag(item)
                                }
                            }.pickerStyle(.menu)
                            Toggle("Ricevi notifiche", isOn: $enabled)
                            if supportedLabels.contains("persona") { Toggle("Persone", isOn: $person) }
                            if supportedLabels.contains("animale") { Toggle("Animali", isOn: $animal) }
                            if supportedLabels.contains("veicolo") { Toggle("Veicoli", isOn: $vehicle) }
                            if supportedLabels.contains("movimento") { Toggle("Movimento ONVIF", isOn: $motion) }
                            Button(busy ? "Salvataggio…" : "Salva avvisi") { Task { await save() } }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                                .disabled(busy || target.isEmpty || selectedLabels.isEmpty)
                            Button("Invia notifica di prova", systemImage: "bell") { Task { await test() } }
                                .buttonStyle(.bordered).tint(Theme.accentSoft).disabled(busy || target.isEmpty)
                        }
                        if !status.isEmpty {
                            Text(status).font(.footnote).foregroundStyle(status.hasPrefix("Errore") ? Color.orange : Color.green)
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding(14)
        }
        .background { Theme.background.ignoresSafeArea() }
        .navigationTitle("Notifiche")
        .task { await load() }
        .onChange(of: target) { _, value in
            let choice = subscriptions[value]
            enabled = choice?.enabled ?? false
            person = choice?.labels.contains("persona") ?? true
            animal = choice?.labels.contains("animale") ?? true
            vehicle = choice?.labels.contains("veicolo") ?? true
            motion = choice?.labels.contains("movimento") ?? true
        }
    }

    private func load() async {
        do {
            let settings = try await store.notifySettings()
            targets = settings.targets
            supportedLabels = settings.labels ?? (store.baseURL?.port == 8766 ? ["movimento"] : ["persona", "animale", "veicolo"])
            subscriptions = settings.subscriptions
            let saved = UserDefaults.standard.string(forKey: "notify-device") ?? ""
            target = targets.contains(saved) ? saved : (targets.first ?? "")
            status = ""
        } catch { status = "Errore: \(error.localizedDescription)" }
    }

    private func save() async {
        busy = true
        do {
            let updated = try await store.saveNotify(target: target, enabled: enabled, labels: selectedLabels)
            subscriptions = updated.subscriptions
            UserDefaults.standard.set(target, forKey: "notify-device")
            status = "Impostazioni salvate"
        } catch { status = "Errore: \(error.localizedDescription)" }
        busy = false
    }

    private var selectedLabels: [String] {
        [(person, "persona"), (animal, "animale"), (vehicle, "veicolo"), (motion, "movimento")]
            .compactMap { $0.0 && supportedLabels.contains($0.1) ? $0.1 : nil }
    }

    private func test() async {
        busy = true
        do { try await store.testNotify(target: target); status = "Notifica di prova inviata a Home Assistant Companion" }
        catch { status = "Errore: \(error.localizedDescription)" }
        busy = false
    }
}
