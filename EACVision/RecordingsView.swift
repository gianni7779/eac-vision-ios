import AVKit
import Combine
import SwiftUI

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
    @State private var previewUnavailable = false
    @State private var lastPreview = Date.distantPast
    @State private var error = ""
    @State private var audioOn = true
    @State private var zoom = 1.0
    @State private var zoomRequest = 0
    @State private var speed = 1.0
    @State private var playing = false
    @State private var armedJump: RecordingJump?
    @State private var showAllEvents = false
    @State private var loadingSegments = false
    @State private var loadRequest = UUID()

    private var camera: NvrCamera? { store.allCameras.first { $0.id == cameraId } }
    private var dayStart: Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: day)?.timeIntervalSince1970 ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !inStack { header }
                if !error.isEmpty { errorBanner }
                cameraPicker
                dayPicker
                recordingStage
                playbackControls
                timelineCard
                eventsCard
            }
            .padding(.horizontal, 14)
            .padding(.top, inStack ? 10 : 18)
            .padding(.bottom, 30)
        }
        .background { Theme.background.ignoresSafeArea() }
        .navigationTitle("Registrazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(inStack ? .visible : .hidden, for: .navigationBar)
        .task(id: store.allCameras) {
            if cameraId.isEmpty {
                if let initialCameraId, store.allCameras.contains(where: { $0.id == initialCameraId }) {
                    cameraId = initialCameraId
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
                  player.currentItem != nil, player.currentTime().seconds.isFinite else { return }
            seconds = max(0, min(86399, segment.start - dayStart + player.currentTime().seconds))
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notice in
            guard let ended = notice.object as? AVPlayerItem, ended === player.currentItem,
                  let index = segments.firstIndex(where: { $0.name == activeName }),
                  index + 1 < segments.count else { return }
            playSegment(segments[index + 1], offset: 0)
        }
        .onDisappear { player.pause(); previewPlayer.pause(); playing = false }
        .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("EACLogo").resizable().scaledToFit().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("EAC VISION").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Theme.accentSoft)
                Text("Registrazioni").font(.system(size: 27, weight: .bold, design: .rounded))
            }
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accentSoft)
                .frame(width: 40, height: 40).background(Theme.panel2, in: Circle())
        }
    }

    private var errorBanner: some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var cameraPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("TELECAMERA", symbol: "video.fill")
            Menu {
                ForEach(store.allCameras) { item in
                    Button(item.name, systemImage: item.id == cameraId ? "checkmark.circle.fill" : "video") {
                        Haptics.tap()
                        cameraId = item.id
                    }
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "video.fill").foregroundStyle(Theme.accentSoft)
                        .frame(width: 36, height: 36).background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(camera?.name ?? "Scegli una telecamera").font(.subheadline.bold()).lineLimit(1)
                        Text(camera?.recording == true ? "Registrazione continua" : "Video disponibili")
                            .font(.caption2).foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(Theme.dim)
                }
                .padding(11)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
            }
            .disabled(store.allCameras.isEmpty)
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel("GIORNO", symbol: "calendar")
                Spacer()
                Text("\(days.count) \(days.count == 1 ? "giorno" : "giorni")")
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.day) { item in
                        Button { selectDay(item.day) } label: {
                            Text(dayTitle(item.day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.day == day ? .white : Theme.dim)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(item.day == day ? Theme.accent.opacity(0.35) : Theme.panel,
                                            in: Capsule())
                                .overlay(Capsule().stroke(item.day == day ? Theme.accent : Theme.line))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                    if days.isEmpty {
                        Text("Nessun giorno disponibile").font(.caption).foregroundStyle(Theme.dim)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var recordingStage: some View {
        ZStack {
            Color.black
            ZoomablePlayerSurface(player: player, onZoom: { zoom = Double($0) },
                                  zoomRequest: zoomRequest, requestedZoom: CGFloat(zoom))
                .opacity(dragging ? 0 : 1)
                .allowsHitTesting(!dragging)
            PlayerSurface(player: previewPlayer)
                .opacity(dragging ? 1 : 0)
                .allowsHitTesting(false)
            if segments.isEmpty && !loadingSegments {
                VStack(spacing: 9) {
                    Image(systemName: "video.slash").font(.title2).foregroundStyle(Theme.dim)
                    Text("Nessuna registrazione per questo giorno")
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }
                .padding()
            }
            if dragging && previewUnavailable {
                Label("Nessun video a quest'ora", systemImage: "video.slash")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(11).background(.black.opacity(0.75), in: Capsule())
            }
            if loadingSegments { ProgressView().tint(Theme.accentSoft).scaleEffect(1.3) }
            VStack {
                HStack {
                    Label(dragging ? "ANTEPRIMA" : "REGISTRAZIONE", systemImage: dragging ? "hand.draw" : "record.circle")
                        .font(.system(size: 10, weight: .bold)).tracking(1)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.68), in: Capsule())
                    Spacer()
                    if zoom > 1.05 && !dragging {
                        Text("\(zoom.formatted(.number.precision(.fractionLength(1))))×")
                            .font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                }
                Spacer()
                HStack {
                    Text(clock(seconds)).font(.system(size: 18, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(dragging ? "Trascina per cercare" : "\(dayTitle(day))")
                        .font(.caption.bold())
                }
                .padding(10)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(10)
            .allowsHitTesting(false)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private var playbackControls: some View {
        VStack(spacing: 13) {
            HStack(spacing: 19) {
                Spacer(minLength: 0)
                transportButton("Indietro 10 secondi", symbol: "gobackward.10") { play(at: max(0, seconds - 10)) }
                Button {
                    Haptics.tap()
                    if playing { player.pause(); playing = false }
                    else { player.play(); player.rate = Float(speed); playing = true }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 12)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(playing ? "Pausa" : "Riprendi")
                .disabled(segments.isEmpty)
                transportButton("Avanti 10 secondi", symbol: "goforward.10") { play(at: min(86399, seconds + 10)) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button {
                    audioOn.toggle()
                    player.isMuted = !audioOn
                    Haptics.tap()
                } label: {
                    Label(audioOn ? "Audio attivo" : "Audio spento",
                          systemImage: audioOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(audioOn ? "Disattiva audio" : "Attiva audio")
                Spacer()
                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0, 8.0, 16.0], id: \.self) { value in
                        Button("\(value.formatted())×", systemImage: speed == value ? "checkmark" : "speedometer") {
                            speed = value
                            if player.rate > 0 { player.rate = Float(value) }
                        }
                    }
                } label: {
                    Label("\(speed.formatted())×", systemImage: "speedometer")
                }
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(Theme.accentSoft)
            HStack(spacing: 8) {
                Text("ZOOM").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Theme.dim)
                Spacer()
                Button { setZoom(max(1, zoom - 0.5)) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Riduci zoom")
                Text("\(zoom.formatted(.number.precision(.fractionLength(1))))×")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim).frame(minWidth: 34)
                Button { setZoom(min(6, zoom + 0.5)) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Aumenta zoom")
                Button("Adatta") { setZoom(1) }
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(Theme.accentSoft)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private func transportButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white).frame(width: 48, height: 48)
                .background(Theme.panel2, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .disabled(segments.isEmpty)
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("LINEA DEL TEMPO", symbol: "clock")
                Spacer()
                Menu {
                    ForEach(0..<24, id: \.self) { hour in
                        Button(String(format: "%02d:00", hour)) { play(at: Double(hour * 3600)) }
                    }
                } label: {
                    Label("Vai a ora", systemImage: "clock.arrow.circlepath")
                        .font(.caption.bold()).foregroundStyle(Theme.accentSoft)
                }
                .disabled(segments.isEmpty)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(clock(seconds)).font(.system(size: 29, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).contentTransition(.numericText())
                Spacer()
                Button("Ultima") {
                    guard let last = segments.last else { return }
                    play(at: max(0, min(86399, last.start + last.dur - dayStart - 5)))
                }
                .font(.caption.bold()).foregroundStyle(Theme.accentSoft)
                .disabled(segments.isEmpty)
            }
            timelineTrack
            HStack {
                Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.dim)
            Text("Trascina sulla linea: il video mostra subito l'anteprima dell'ora scelta.")
                .font(.caption2).foregroundStyle(Theme.dim)
            if !recordingEvents.isEmpty {
                HStack(spacing: 12) {
                    legendDot("Persone", color: .orange)
                    legendDot("Animali", color: .green)
                    legendDot("Veicoli", color: .purple)
                }
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
        }
        .padding(15)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private var timelineTrack: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            Canvas { context, size in
                let track = CGRect(x: 0, y: 15, width: size.width, height: 10)
                context.fill(Path(roundedRect: track, cornerRadius: 5), with: .color(.white.opacity(0.15)))
                for segment in segments {
                    let left = max(0, min(1, (segment.start - dayStart) / 86400))
                    let right = max(left, min(1, (segment.start + segment.dur - dayStart) / 86400))
                    let rect = CGRect(x: size.width * CGFloat(left), y: 15,
                                      width: max(1, size.width * CGFloat(right - left)), height: 10)
                    context.fill(Path(rect), with: .color(Theme.accent))
                }
                for event in recordingEvents {
                    let position = (event.start / 1000 - dayStart) / 86400
                    guard position >= 0 && position < 1 else { continue }
                    let rect = CGRect(x: max(0, size.width * CGFloat(position) - 2), y: 10, width: 4, height: 20)
                    context.fill(Path(rect), with: .color(eventColor(event.label)))
                }
                let marker = max(0, min(size.width - 2, size.width * CGFloat(seconds / 86400)))
                context.fill(Path(CGRect(x: marker, y: 5, width: 2, height: 29)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: max(0, marker - 6), y: 12, width: 14, height: 14)),
                             with: .color(.white))
            }
            .frame(width: width, height: 40)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !segments.isEmpty else { return }
                    if !dragging { dragging = true; player.pause(); playing = false }
                    seconds = max(0, min(86399, Double(value.location.x / width) * 86400))
                    showPreview(seconds, force: previewPlayer.currentItem == nil)
                }
                .onEnded { _ in
                    guard dragging else { return }
                    dragging = false
                    previewUnavailable = false
                    previewPlayer.pause()
                    play(at: seconds)
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Linea delle registrazioni")
            .accessibilityValue(clock(seconds))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: play(at: min(86399, seconds + 300))
                case .decrement: play(at: max(0, seconds - 300))
                @unknown default: break
                }
            }
        }
        .frame(height: 40)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("EVENTI DEL GIORNO", symbol: "sparkles")
                Spacer()
                Text("\(recordingEvents.count)").font(.caption.bold()).foregroundStyle(Theme.accentSoft)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
            }
            if recordingEvents.isEmpty {
                Text("Nessun evento rilevato in questa giornata.")
                    .font(.subheadline).foregroundStyle(Theme.dim).padding(.vertical, 8)
            } else {
                ForEach(Array(recordingEvents.prefix(showAllEvents ? recordingEvents.count : 8))) { event in
                    Button {
                        Haptics.tap()
                        play(at: max(0, event.start / 1000 - dayStart - 5))
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: eventSymbol(event.label))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(eventColor(event.label))
                                .frame(width: 36, height: 36)
                                .background(eventColor(event.label).opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.label.capitalized).font(.subheadline.bold()).foregroundStyle(.white)
                                Text(clock(event.start / 1000 - dayStart))
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if event.score > 0 {
                                Text("\(Int((event.score * 100).rounded()))%")
                                    .font(.caption.bold()).foregroundStyle(Theme.dim)
                            }
                            Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Theme.accentSoft)
                        }
                        .padding(9)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                if recordingEvents.count > 8 {
                    Button(showAllEvents ? "Mostra meno" : "Mostra tutti gli eventi") {
                        showAllEvents.toggle()
                    }
                    .font(.caption.bold()).foregroundStyle(Theme.accentSoft)
                    .frame(maxWidth: .infinity).padding(.top, 4)
                }
            }
        }
        .padding(15)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .bold)).tracking(1.2)
            .foregroundStyle(Theme.accentSoft)
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(title) }
    }

    private func eventColor(_ label: String) -> Color {
        switch label {
        case "persona": return .orange
        case "animale": return .green
        case "veicolo": return .purple
        default: return .gray
        }
    }

    private func eventSymbol(_ label: String) -> String {
        switch label {
        case "persona": return "person.fill"
        case "animale": return "pawprint.fill"
        case "veicolo": return "car.fill"
        default: return "waveform"
        }
    }

    private func dayTitle(_ value: String) -> String {
        guard !value.isEmpty else { return "Giorno" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: value) else { return value }
        if Calendar.current.isDateInToday(date) { return "Oggi" }
        if Calendar.current.isDateInYesterday(date) { return "Ieri" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func clock(_ value: Double) -> String {
        let s = max(0, min(86399, Int(value.isFinite ? value : 0)))
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
        play(at: max(0, min(86399, jump.at)))
    }

    private func segment(at value: Double) -> NvrSegment? {
        let target = dayStart + value
        return segments.first { $0.start <= target && target < $0.start + $0.dur }
            ?? segments.first { $0.start > target } ?? segments.last
    }

    private func play(at value: Double) {
        guard let segment = segment(at: value) else { return }
        let offset = max(0, min(segment.dur - 0.1, dayStart + value - segment.start))
        seconds = max(0, min(86399, segment.start - dayStart + offset))
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
        let target = dayStart + value
        guard let segment = segments.first(where: { $0.start <= target && target < $0.start + $0.dur }) else {
            previewUnavailable = true
            previewPlayer.pause()
            previewPlayer.replaceCurrentItem(with: nil)
            previewName = ""
            return
        }
        previewUnavailable = false
        guard force || Date().timeIntervalSince(lastPreview) > 0.2,
              let url = store.endpoint(segment.url) else { return }
        lastPreview = Date()
        let offset = max(0, min(segment.dur - 0.1, dayStart + value - segment.start))
        if previewName != segment.name {
            previewName = segment.name
            previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        previewPlayer.isMuted = true
        previewPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600),
                           toleranceBefore: .zero, toleranceAfter: .zero)
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
            if !days.contains(where: { $0.day == day }) { day = days.first?.day ?? "" }
            if day.isEmpty {
                segments = []
                recordingEvents = []
                player.pause()
                player.replaceCurrentItem(with: nil)
                error = ""
                return
            }
            await loadSegments()
            if missingJump && error.isEmpty { error = "La registrazione di questo evento non è più disponibile." }
        } catch { self.error = error.localizedDescription }
    }

    private func loadSegments() async {
        guard let camera, !day.isEmpty else { return }
        let selectedCamera = camera.id, selectedDay = day
        let requestID = UUID()
        loadRequest = requestID
        loadingSegments = true
        player.pause()
        previewPlayer.pause()
        playing = false
        setZoom(1)
        player.replaceCurrentItem(with: nil)
        do {
            let loaded = try await store.segments(for: camera, day: selectedDay)
            guard loadRequest == requestID, cameraId == selectedCamera && day == selectedDay else { return }
            segments = loaded.filter { $0.live != true && $0.dur > 0 }.sorted { $0.start < $1.start }
            let dayStartMs = dayStart * 1000
            recordingEvents = ((try? await store.events(for: camera, day: selectedDay)) ?? [])
                .filter { $0.cam == camera.id && $0.start >= dayStartMs && $0.start < dayStartMs + 86400000 }
            guard loadRequest == requestID else { return }
            activeName = ""
            previewName = ""
            showAllEvents = false
            if armedJump != nil { seekToArmedJump() }
            else if let first = segments.first { play(at: max(0, first.start - dayStart)) }
            else { seconds = 0 }
            error = ""
            loadingSegments = false
        } catch {
            guard loadRequest == requestID else { return }
            self.error = error.localizedDescription
            loadingSegments = false
        }
    }
}
