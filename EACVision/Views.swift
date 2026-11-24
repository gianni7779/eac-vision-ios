import AVKit
import Combine
import SwiftUI
import UIKit

private let appBackground = Color(red: 12/255, green: 23/255, blue: 37/255)
private let panel = Color(red: 23/255, green: 40/255, blue: 58/255)
private let panel2 = Color(red: 32/255, green: 55/255, blue: 75/255)
private let accent = Color(red: 34/255, green: 163/255, blue: 227/255)
private let dim = Color(red: 169/255, green: 190/255, blue: 207/255)
private let line = Color(red: 95/255, green: 155/255, blue: 190/255).opacity(0.35)

struct CamerasView: View {
    @EnvironmentObject private var store: NvrStore
    let onNavigate: (AppPage) -> Void
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.error.isEmpty {
                Text(store.error).font(.footnote).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            if store.cameras.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image("EACLogo").resizable().scaledToFit().frame(width: 90, height: 90)
                    Text("Nessuna telecamera nella vista").font(.title3.bold())
                    Text("Aggiungi le camere con ONVIF in Home Assistant e selezionale nella vista principale.")
                        .font(.subheadline).foregroundStyle(dim).multilineTextAlignment(.center)
                    Button("Impostazioni", systemImage: "gearshape") { onNavigate(.settings) }
                        .buttonStyle(.borderedProminent).tint(accent)
                }.padding(24)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: store.cameras.count == 1 ? [GridItem(.flexible())] : columns, spacing: 6) {
                        ForEach(store.cameras) { camera in
                            NavigationLink(value: camera) {
                                CameraTile(camera: camera, live: (store.cameras.firstIndex(of: camera) ?? 0) < 4)
                            }
                                .buttonStyle(.plain)
                        }
                    }.padding(6)
                }
                .refreshable { await store.refreshCameras() }
            }
        }
        .background(appBackground)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image("EACLogo").resizable().scaledToFit().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EAC Vision").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    Text("Electronic Ascione Company").font(.system(size: 10)).foregroundStyle(dim)
                }
                Spacer(minLength: 3)
                headerButton("clock.arrow.circlepath") { onNavigate(.recordings) }
                headerButton("video") { Task { await store.refreshCameras() } }
                Menu {
                    Button("Registrazioni", systemImage: "clock.arrow.circlepath") { onNavigate(.recordings) }
                    Button("Eventi AI", systemImage: "sparkles") { onNavigate(.events) }
                    Button("Impostazioni", systemImage: "gearshape") { onNavigate(.settings) }
                } label: { headerIcon("line.3.horizontal") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Label(store.viewName, systemImage: "square.grid.2x2")
                        .font(.system(size: 13, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 9)
                        .background(panel2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                    Label(store.layoutName, systemImage: "square.grid.3x3")
                        .font(.system(size: 13, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 9)
                        .background(panel2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                    Label("Audio disattivato", systemImage: "speaker.slash")
                        .font(.system(size: 12)).foregroundStyle(dim)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appBackground)
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerIcon(symbol) }.buttonStyle(.plain)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white).frame(width: 36, height: 34)
            .background(panel2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
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
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            Text(camera.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                .shadow(color: .black, radius: 3).padding(8)
            Text(live && streamReady ? (camera.recording == true ? "REC" : "LIVE") : "APRI")
                .font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
                .background(camera.recording == true ? Color.red.opacity(0.85) : accent.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(7)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
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
    @State private var player = AVPlayer()
    @State private var audioOn = false
    @State private var controlsVisible = true
    @State private var streamReady = false
    @State private var streamMode = 0
    @State private var streamAttempt = 0
    @State private var snapshotTick = 0
    @State private var streamMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraSnapshot(camera: camera, tick: snapshotTick)
                .aspectRatio(16/9, contentMode: .fit)
            PlayerSurface(player: player, onReady: { ready in
                streamReady = ready
                if ready { streamMessage = "" }
            })
                .aspectRatio(16/9, contentMode: .fit)
                .opacity(streamReady ? 1 : 0.01)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { controlsVisible.toggle() } }
            if controlsVisible {
                VStack {
                    HStack(spacing: 10) {
                        Button { dismiss() } label: { Label("Indietro", systemImage: "chevron.left") }
                        Spacer()
                        Text(camera.name).font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        Text("LIVE").font(.caption2.bold()).foregroundStyle(accent)
                    }
                    .padding(12).background(panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                    if !streamReady {
                        Text(streamMessage.isEmpty ? "Collegamento al live… Anteprima disponibile." : streamMessage)
                            .font(.caption).foregroundStyle(.white)
                            .padding(10).background(panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                    } else if streamMode == 1 {
                        Text("Formato H.264 compatibile attivo; l'audio non è disponibile in questo flusso.")
                            .font(.caption).foregroundStyle(.white)
                            .padding(10).background(panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                    HStack(spacing: 9) {
                        Button {
                            audioOn.toggle()
                            player.isMuted = !audioOn
                        } label: {
                            Label(audioOn ? "Audio attivo" : "Audio", systemImage: audioOn ? "speaker.wave.2" : "speaker.slash")
                        }
                        .disabled(streamMode == 1)
                        Button { streamMode = 0; start() } label: { Label("Ricollega", systemImage: "arrow.clockwise") }
                        NavigationLink(value: AppPage.recordings) {
                            Label("Archivio", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                }.padding(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { start() }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
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

    private func start() {
        var query = [URLQueryItem(name: "src", value: camera.id)]
        if streamMode == 1 { query.append(URLQueryItem(name: "mode", value: "ts")) }
        guard let url = store.endpoint("/eacnvr/hls.m3u8", query: query) else { return }
        streamReady = false
        streamMessage = streamMode == 1 ? "Provo il formato video alternativo…" : ""
        streamAttempt += 1
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = !audioOn
        player.play()
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
                    .font(.caption2).foregroundStyle(dim).padding(8)
            }
            default: Color.black.overlay { ProgressView().tint(accent) }
            }
        }
    }
}

struct RecordingsView: View {
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

    private var camera: NvrCamera? { store.cameras.first { $0.id == cameraId } }
    private var dayStart: Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: day)?.timeIntervalSince1970 ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image("EACLogo").resizable().scaledToFit().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REGISTRAZIONI").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(accent)
                        Text("Archivio video").font(.title2.bold())
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.footnote) }
                Picker("Telecamera", selection: $cameraId) {
                    ForEach(store.cameras) { camera in Text(camera.name).tag(camera.id) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.day) { item in
                            Button(item.day) { day = item.day }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(item.day == day ? Color(red: 20/255, green: 95/255, blue: 134/255) : panel2,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.day == day ? accent : line))
                        }
                    }
                }
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                Text(dragging ? "Anteprima · \(clock(seconds))" : "\(day) · \(clock(seconds))")
                    .font(.headline.monospacedDigit())
                if dragging {
                    PlayerSurface(player: previewPlayer)
                        .frame(height: 150)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10))
                }
                Slider(value: $seconds, in: 0...86399, onEditingChanged: { editing in
                    dragging = editing
                    if editing { showPreview(seconds, force: true) }
                    else { play(at: seconds); previewPlayer.pause() }
                })
                .onChange(of: seconds) { _, value in if dragging { showPreview(value) } }
                .disabled(segments.isEmpty)
                .tint(accent)
                HStack { Text("00:00"); Spacer(); Text("Trascina per vedere l'anteprima"); Spacer(); Text("24:00") }
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Azzurro: video disponibile · Segni colorati: eventi AI").font(.caption).foregroundStyle(dim)
                coverage
                HStack(spacing: 16) {
                    eventLegend("Persone", color: .orange)
                    eventLegend("Animali", color: .green)
                    eventLegend("Veicoli", color: .purple)
                }.font(.caption2).foregroundStyle(dim)
                if segments.isEmpty { ContentUnavailableView("Nessun video", systemImage: "clock", description: Text("Scegli una camera e un giorno con registrazioni.")) }
            }.padding()
        }
        .background(appBackground)
        .navigationTitle("Registrazioni")
        .toolbar(.visible, for: .navigationBar)
        .task(id: store.cameras) {
            if cameraId.isEmpty, let first = store.cameras.first { cameraId = first.id }
        }
        .onChange(of: cameraId) { _, _ in Task { await loadDays() } }
        .onChange(of: day) { _, _ in Task { await loadSegments() } }
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
        .onDisappear { player.pause(); previewPlayer.pause() }
    }

    private var coverage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                ForEach(segments, id: \.name) { segment in
                    let left = CGFloat(max(0, (segment.start - dayStart) / 86400))
                    let width = CGFloat(max(0, min(segment.dur / 86400, Double(1 - left))))
                    Capsule().fill(accent).frame(width: proxy.size.width * width)
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
        default: return .gray
        }
    }

    private func clock(_ value: Double) -> String {
        let s = max(0, min(86399, Int(value)))
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
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
        player.play()
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
        previewPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loadDays() async {
        guard let camera else { return }
        do {
            days = try await store.days(for: camera)
            day = days.first?.day ?? ""
            if day.isEmpty { segments = []; recordingEvents = []; player.pause(); player.replaceCurrentItem(with: nil) }
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    private func loadSegments() async {
        guard let camera, !day.isEmpty else { return }
        do {
            player.pause()
            player.replaceCurrentItem(with: nil)
            segments = try await store.segments(for: camera, day: day)
            segments = segments.filter { $0.live != true && $0.dur > 0 }.sorted { $0.start < $1.start }
            let dayStartMs = dayStart * 1000
            recordingEvents = ((try? await store.events(for: camera, day: day)) ?? [])
                .filter { $0.cam == camera.id && $0.start >= dayStartMs && $0.start < dayStartMs + 86400000 }
            activeName = ""
            previewName = ""
            if let first = segments.first {
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image("EACLogo").resizable().scaledToFit().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EAC VISION AI").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(accent)
                        Text("Eventi").font(.title2.bold())
                    }
                    Spacer()
                }
                if !error.isEmpty { Text(error).foregroundStyle(.orange).padding() }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        AsyncImage(url: store.endpoint("/eacnvr/event.jpg", query: [URLQueryItem(name: "id", value: event.id)])) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Rectangle().fill(.black).aspectRatio(16/9, contentMode: .fit) }
                        Text(event.label.capitalized).font(.headline)
                        Text("\(event.camName) · \(Date(timeIntervalSince1970: event.start / 1000).formatted(date: .abbreviated, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10).background(panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(line))
                }
                if events.isEmpty && error.isEmpty { ContentUnavailableView("Nessun evento", systemImage: "sparkles", description: Text("L'edizione AI mostra qui persone, veicoli e animali rilevati.")) }
            }.padding()
        }
        .background(appBackground)
        .navigationTitle("Eventi AI")
        .toolbar(.visible, for: .navigationBar)
        .task { await refresh() }
        .refreshable { await refresh() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image("EACLogo").resizable().scaledToFit().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EAC Vision").font(.title2.bold())
                        Text("COLLEGA IL REGISTRATORE").font(.system(size: 10, weight: .bold))
                            .tracking(1.2).foregroundStyle(accent)
                    }
                }
                Text("Indirizzo Home Assistant o Tailscale").font(.subheadline.bold())
                TextField("Indirizzo del dispositivo HA", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12).background(panel2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                Text("Codice delle app").font(.subheadline.bold())
                SecureField("Codice delle app", text: $key)
                    .padding(12).background(panel2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
                Button(busy ? "Collegamento…" : "Collega") {
                    Task {
                        busy = true
                        do { try await store.connect(address: address, key: key); error = "" }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
                .disabled(busy).buttonStyle(.borderedProminent).tint(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                if store.connected { Label("Collegato a \(store.name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Divider().overlay(line)
                Text("COLLEGAMENTO FUORI CASA").font(.system(size: 11, weight: .bold))
                    .tracking(1.2).foregroundStyle(accent)
                Text("In casa puoi inserire l'IP o l'indirizzo normale di Home Assistant, anche con :8123. EAC Vision prova automaticamente la porta 8766 e la 8767.")
                Text("Tailscale: usa l'IP 100.x.y.z del dispositivo HA e verifica da Safari che http://100.x.y.z:8766/eacnvr/info (o :8767 per AI) si apra.")
                Text("DuckDNS: usa https://tuodominio.duckdns.org con un proxy HTTPS che inoltra /eacnvr/. L'indirizzo HA sulla porta 8123 non basta.")
                Text("Il codice si trova in EAC Vision Home Assistant → Impostazioni → PC, TV e telefono.")
                    .foregroundStyle(dim)
            }
            .font(.subheadline)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(appBackground)
        .navigationTitle("Impostazioni")
        .toolbar(.visible, for: .navigationBar)
        .onAppear { address = store.address; key = store.key }
    }
}
