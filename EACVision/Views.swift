import AVKit
import SwiftUI
import UIKit

private let background = Color(red: 0.025, green: 0.08, blue: 0.13)
private let panel = Color(red: 0.07, green: 0.18, blue: 0.26)

struct CamerasView: View {
    @EnvironmentObject private var store: NvrStore
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.name).font(.title2.bold())
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.orange) }
                if store.cameras.isEmpty { ContentUnavailableView("Nessuna telecamera", systemImage: "video.slash", description: Text("Controlla l'integrazione ONVIF in Home Assistant.")) }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.cameras) { camera in
                        NavigationLink(value: camera) {
                            VStack(alignment: .leading, spacing: 5) {
                                AsyncImage(url: store.endpoint("/eacnvr/snapshot", query: [URLQueryItem(name: "cam", value: camera.id)])) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Rectangle().fill(.black).overlay { ProgressView() }
                                }
                                .frame(maxWidth: .infinity).aspectRatio(16/9, contentMode: .fit)
                                Text(camera.name).font(.subheadline.bold()).lineLimit(1).padding(.horizontal, 8)
                                Text(camera.recording == true ? "● REC" : "LIVE").font(.caption2).foregroundStyle(camera.recording == true ? Color.red : Color.cyan).padding(.horizontal, 8).padding(.bottom, 8)
                            }
                            .background(panel, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.padding()
        }
        .background(background)
        .navigationTitle("Telecamere")
        .navigationDestination(for: NvrCamera.self) { CameraDetailView(camera: $0) }
        .refreshable { await store.refreshCameras() }
    }
}

struct CameraDetailView: View {
    @EnvironmentObject private var store: NvrStore
    let camera: NvrCamera
    @State private var player = AVPlayer()
    @State private var audioOn = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VideoPlayer(player: player)
                .aspectRatio(16/9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button(audioOn ? "Disattiva audio" : "Attiva audio", systemImage: audioOn ? "speaker.wave.2" : "speaker.slash") {
                    audioOn.toggle()
                    player.isMuted = !audioOn
                }.buttonStyle(.bordered)
                Button("Ricollega", systemImage: "arrow.clockwise") { start() }.buttonStyle(.bordered)
            }
            Text("Video nel formato originale della telecamera. L'audio dipende dal codec del flusso.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .background(background)
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { start() }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }

    private func start() {
        guard let url = store.endpoint("/eacnvr/hls.m3u8", query: [URLQueryItem(name: "src", value: camera.id)]) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = !audioOn
        player.play()
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.videoLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: PlayerLayerView, context: Context) { view.videoLayer.player = player }
}

struct RecordingsView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var cameraId = ""
    @State private var day = ""
    @State private var days: [NvrDay] = []
    @State private var segments: [NvrSegment] = []
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Archivio video").font(.title2.bold())
                if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.footnote) }
                Picker("Telecamera", selection: $cameraId) {
                    ForEach(store.cameras) { camera in Text(camera.name).tag(camera.id) }
                }.pickerStyle(.menu)
                Picker("Giorno", selection: $day) {
                    ForEach(days, id: \.day) { item in Text(item.day).tag(item.day) }
                }.pickerStyle(.menu)
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                HStack { Text("00:00"); Spacer(); Text("Trascina per vedere l'anteprima"); Spacer(); Text("24:00") }
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Parti azzurre: video disponibile").font(.caption).foregroundStyle(.secondary)
                coverage
                if segments.isEmpty { ContentUnavailableView("Nessun video", systemImage: "clock", description: Text("Scegli una camera e un giorno con registrazioni.")) }
            }.padding()
        }
        .background(background)
        .navigationTitle("Registrazioni")
        .task(id: store.cameras) {
            if cameraId.isEmpty, let first = store.cameras.first { cameraId = first.id }
        }
        .onChange(of: cameraId) { _, _ in Task { await loadDays() } }
        .onChange(of: day) { _, _ in Task { await loadSegments() } }
        .onDisappear { player.pause(); previewPlayer.pause() }
    }

    private var coverage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                ForEach(segments, id: \.name) { segment in
                    let left = CGFloat(max(0, (segment.start - dayStart) / 86400))
                    let width = CGFloat(max(0, min(segment.dur / 86400, Double(1 - left))))
                    Capsule().fill(.cyan).frame(width: proxy.size.width * width)
                        .offset(x: proxy.size.width * left)
                }
            }
        }.frame(height: 10)
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
        guard let segment = segment(at: value), let url = store.endpoint(segment.url) else { return }
        let offset = max(0, min(segment.dur - 0.1, dayStart + value - segment.start))
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
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    private func loadSegments() async {
        guard let camera, !day.isEmpty else { return }
        do {
            segments = try await store.segments(for: camera, day: day)
            segments = segments.filter { $0.live != true && $0.dur > 0 }.sorted { $0.start < $1.start }
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
                }
                if events.isEmpty && error.isEmpty { ContentUnavailableView("Nessun evento", systemImage: "sparkles", description: Text("L'edizione AI mostra qui persone, veicoli e animali rilevati.")) }
            }.padding()
        }
        .background(background)
        .navigationTitle("Eventi AI")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do { events = try await store.events(); error = "" }
        catch { error = "Gli eventi AI sono disponibili con EAC Vision AI su mini PC. \(error.localizedDescription)" }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var store: NvrStore
    @State private var address = ""
    @State private var key = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        Form {
            Section("Collega EAC Vision NVR") {
                TextField("Indirizzo del dispositivo HA", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Codice delle app", text: $key)
                Button(busy ? "Collegamento…" : "Collega") {
                    Task {
                        busy = true
                        do { try await store.connect(address: address, key: key); error = "" }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }.disabled(busy)
                if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                if store.connected { Label("Collegato a \(store.name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Section("Esempi") {
                Text("Tailscale: http://100.x.y.z:8766 per la versione senza AI, oppure :8767 per l'edizione AI.")
                Text("DuckDNS: usa https://tuodominio.duckdns.org con un proxy HTTPS che inoltra /eacnvr/. L'indirizzo HA sulla porta 8123 non basta.")
                Text("Il codice si trova in EAC Vision Home Assistant → Impostazioni → PC, TV e telefono.")
            }
        }
        .navigationTitle("Impostazioni")
        .onAppear { address = store.address; key = store.key }
    }
}
