import AVKit
import SwiftUI

private struct LocalLiveCamera: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
}

/// Flussi HLS salvati solo sull'iPhone: non modificano le telecamere o le registrazioni dell'NVR.
struct LocalCamerasView: View {
    @AppStorage("eac-local-mode") private var localMode = false
    @AppStorage("eac-local-audio") private var audioCameraId = ""
    @AppStorage("eac-grid-cols") private var gridColumns = 2
    @AppStorage("eac-show-camera-names") private var showNames = true
    @State private var cameras = LocalCamerasView.load()
    @State private var opened: LocalLiveCamera?
    @State private var adding = false
    @State private var name = ""
    @State private var address = ""
    @State private var error = ""
    @State private var reordering = false
    @State private var moveSource: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image("EACLogo").resizable().scaledToFit().frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text("Telecamere solo live").font(.headline)
                    Text("Salvate su questo iPhone").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Menu {
                    Button("Aggiungi telecamera", systemImage: "plus") { adding = true }
                    Button(reordering ? "Termina riordino" : "Sposta telecamere", systemImage: "arrow.left.arrow.right") {
                        reordering.toggle(); moveSource = nil
                    }
                    Button("Griglia: \(gridColumns) colonne", systemImage: "square.grid.2x2") {
                        gridColumns = gridColumns % 3 + 1
                    }
                    Button("Collega EAC Vision NVR", systemImage: "externaldrive") { localMode = false }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(12)

            if reordering {
                Text(moveSource == nil ? "Tocca la camera da spostare" : "Tocca la nuova posizione")
                    .font(.footnote).foregroundStyle(Theme.accent).padding(.bottom, 8)
            }
            if cameras.isEmpty {
                Spacer()
                Image(systemName: "video.badge.plus").font(.system(size: 46)).foregroundStyle(Theme.accent)
                Text("Nessuna telecamera solo live").font(.headline)
                Text("Per ONVIF o RTSP collega EAC Vision NVR. Qui puoi aggiungere un indirizzo HLS della telecamera.")
                    .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center).padding(.horizontal, 30)
                Button("Aggiungi telecamera") { adding = true }
                    .buttonStyle(.borderedProminent)
                Button("Collega EAC Vision NVR") { localMode = false }
                    .buttonStyle(.bordered)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: min(3, max(1, gridColumns))), spacing: 8) {
                        ForEach(cameras) { camera in
                            Button {
                                if reordering {
                                    if let source = moveSource {
                                        swap(source, camera.id)
                                        moveSource = nil
                                    } else { moveSource = camera.id }
                                } else { opened = camera }
                            } label: {
                                LocalCameraTile(camera: camera, live: (cameras.firstIndex(of: camera) ?? 0) < 4 || audioCameraId == camera.id,
                                                audioActive: audioCameraId == camera.id, showName: showNames)
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(moveSource == camera.id ? Theme.accent : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                                guard !reordering else { return }
                                audioCameraId = audioCameraId == camera.id ? "" : camera.id
                            })
                        }
                    }
                    .padding(10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GESTISCI TELECAMERE").font(.caption.bold()).foregroundStyle(Theme.dim)
                        ForEach(cameras) { camera in
                            HStack {
                                Text(camera.name).lineLimit(1)
                                Spacer()
                                Button(role: .destructive) { remove(camera.id) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .padding(10).background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background { Theme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $adding) { addForm }
        .fullScreenCover(item: $opened) { camera in
            LocalCameraDetailView(camera: camera)
        }
    }

    private var addForm: some View {
        NavigationStack {
            Form {
                Section("Telecamera solo live") {
                    TextField("Nome", text: $name)
                    TextField("URL HLS (http:// o https://)", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Il flusso deve essere HLS, di solito un indirizzo .m3u8. Non viene registrato.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Aggiungi telecamera")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { adding = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { add() } }
            }
        }
    }

    private func add() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { error = "Inserisci un URL HLS valido"; return }
        cameras.append(LocalLiveCamera(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Telecamera" : name, url: value))
        save()
        name = ""; address = ""; error = ""; adding = false
    }

    private func swap(_ source: String, _ target: String) {
        guard let from = cameras.firstIndex(where: { $0.id == source }),
              let to = cameras.firstIndex(where: { $0.id == target }) else { return }
        cameras.swapAt(from, to)
        save()
    }

    private func remove(_ id: String) {
        cameras.removeAll { $0.id == id }
        if audioCameraId == id { audioCameraId = "" }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cameras) { UserDefaults.standard.set(data, forKey: "eac-local-cameras") }
    }

    private static func load() -> [LocalLiveCamera] {
        guard let data = UserDefaults.standard.data(forKey: "eac-local-cameras") else { return [] }
        return (try? JSONDecoder().decode([LocalLiveCamera].self, from: data)) ?? []
    }
}

private struct LocalCameraTile: View {
    let camera: LocalLiveCamera
    let live: Bool
    let audioActive: Bool
    let showName: Bool
    @State private var player = AVPlayer()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if live { PlayerSurface(player: player).allowsHitTesting(false) }
            if showName {
                Text(camera.name).font(.caption.bold()).lineLimit(1)
                    .padding(8).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .padding(7)
            }
            if audioActive {
                Image(systemName: "speaker.wave.2.fill").font(.caption)
                    .padding(7).background(Theme.accent, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .onAppear { start() }
        .onChange(of: live) { _, enabled in
            if enabled { start() }
            else { player.pause(); player.replaceCurrentItem(with: nil) }
        }
        .onChange(of: audioActive) { _, value in player.isMuted = !value }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }

    private func start() {
        guard live, let url = URL(string: camera.url) else { return }
        player.isMuted = !audioActive
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}

private struct LocalCameraDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let camera: LocalLiveCamera
    @State private var player = AVPlayer()
    @State private var audio = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZoomablePlayerSurface(player: player)
                .aspectRatio(16/9, contentMode: .fit)
            VStack {
                HStack {
                    Button { dismiss() } label: { Label("Chiudi", systemImage: "xmark.circle.fill") }
                    Spacer()
                    Text(camera.name).font(.headline).lineLimit(1)
                    Spacer()
                    Button { audio.toggle(); player.isMuted = !audio } label: {
                        Image(systemName: audio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                }
                .buttonStyle(.bordered).padding()
                Spacer()
                Text("Solo live · pizzica per ingrandire e spostare l'immagine")
                    .font(.caption).foregroundStyle(Theme.dim).padding()
            }
        }
        .onAppear {
            guard let url = URL(string: camera.url) else { return }
            player.isMuted = true
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }
}
