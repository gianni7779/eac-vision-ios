import Foundation
import Security
import SwiftUI

struct NvrCamera: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let recorded: Bool?
    let recording: Bool?
    let ezPtz: Bool?
    let ezSiren: Bool?
}

struct CameraListResponse: Decodable {
    let name: String
    let cams: [NvrCamera]
}

struct NvrView: Identifiable, Decodable {
    let id: String
    let name: String
    let layout: String
    let slots: [String]
}

struct NvrDay: Decodable, Hashable { let day: String }

struct NvrSegment: Decodable, Hashable {
    let start: Double
    let dur: Double
    let name: String
    let url: String
    let live: Bool?
}

struct NvrEvent: Identifiable, Decodable {
    let id: String
    let cam: String
    let camName: String
    let label: String
    let score: Double
    let start: Double
    let end: Double?
}

struct NotifyChoice: Codable {
    let enabled: Bool
    let labels: [String]
}

struct NotifySettings: Decodable {
    let targets: [String]
    let labels: [String]?
    let subscriptions: [String: NotifyChoice]
}

struct NvrError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private enum KeyStore {
    static let account = "eac-vision-nvr-key"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor
final class NvrStore: ObservableObject {
    @Published var cameras: [NvrCamera] = []
    @Published var name = "EAC Vision NVR"
    @Published var viewName = "Principale"
    @Published var layoutName = "4 riquadri"
    @Published var error = ""
    @Published var connected = false
    @Published var availableViews: [NvrView] = []
    @Published var selectedViewId = UserDefaults.standard.string(forKey: "nvr-view-id") ?? ""
    @Published var address = UserDefaults.standard.string(forKey: "nvr-address") ?? ""
    private(set) var baseURL: URL?
    private(set) var key = KeyStore.read()

    init() {
        let saved = UserDefaults.standard.string(forKey: "nvr-base-url")
        if !address.isEmpty, !key.isEmpty,
           let url = saved.flatMap(URL.init(string:)) ?? (try? Self.parseAddress(address)) {
            baseURL = url
            connected = true
        }
    }

    static func parseAddress(_ text: String) throws -> URL {
        guard let first = try candidateAddresses(text).first else { throw NvrError(message: "Indirizzo non valido") }
        return first
    }

    static func candidateAddresses(_ text: String) throws -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NvrError(message: "Inserisci l'indirizzo del registratore") }
        let value = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              scheme == "http" || scheme == "https" else {
            throw NvrError(message: "Indirizzo non valido")
        }
        if scheme == "http" && !privateHost(host) {
            throw NvrError(message: "Per DuckDNS usa un proxy HTTPS; per Tailscale usa l'IP 100.x.y.z")
        }
        let originalPort = components.port
        components.path = ""
        components.query = nil
        components.fragment = nil
        if privateHost(host) && (originalPort == nil || originalPort == 8123) {
            var httpsURL: URL?
            if scheme == "https" {
                var https = components
                https.port = 443
                httpsURL = https.url
            }
            components.scheme = "http"
            components.port = 8766
            guard let basic = components.url else { throw NvrError(message: "Indirizzo non valido") }
            components.port = 8767
            guard let ai = components.url else { throw NvrError(message: "Indirizzo non valido") }
            return [basic, ai] + (httpsURL.map { [$0] } ?? [])
        }
        if originalPort == 8123 {
            throw NvrError(message: "DuckDNS sulla porta 8123 apre solo Home Assistant: configura il proxy HTTPS per /eacnvr/")
        }
        components.port = originalPort ?? (scheme == "https" ? 443 : 8766)
        guard let url = components.url else { throw NvrError(message: "Indirizzo non valido") }
        if privateHost(host) && scheme == "http" && components.port == 8766 {
            components.port = 8767
            if let ai = components.url { return [url, ai] }
        }
        return [url]
    }

    private static func privateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".ts.net") || !host.contains(".") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 100 && (64...127).contains(parts[1]))
    }

    private func url(_ path: String, query: [URLQueryItem] = [], base: URL? = nil, key: String? = nil) -> URL? {
        guard let base = base ?? baseURL,
              let resolved = URL(string: path, relativeTo: base)?.absoluteURL,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + query + [URLQueryItem(name: "key", value: key ?? self.key)]
        return components.url
    }

    func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL? { url(path, query: query) }

    private func fetch<T: Decodable>(_ path: String, query: [URLQueryItem] = [], base: URL? = nil, key: String? = nil, timeout: TimeInterval = 20) async throws -> T {
        guard let address = url(path, query: query, base: base, key: key) else { throw NvrError(message: "NVR non configurato") }
        var request = URLRequest(url: address)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NvrError(message: "Risposta NVR non valida") }
        if http.statusCode == 403 { throw NvrError(message: "Codice NVR errato") }
        guard http.statusCode == 200 else { throw NvrError(message: "NVR: errore HTTP \(http.statusCode)") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let address = url(path) else { throw NvrError(message: "NVR non configurato") }
        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NvrError(message: "Impossibile salvare le notifiche. Aggiorna EAC Vision AI su Home Assistant.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func selectView(_ cameras: [NvrCamera], from views: [NvrView]) -> [NvrCamera] {
        availableViews = views
        guard let view = views.first(where: { $0.id == selectedViewId }) ?? views.first else { return cameras }
        selectedViewId = view.id
        viewName = view.name
        layoutName = view.layout == "L16" ? "16 riquadri" : view.layout == "L9" ? "9 riquadri" : "4 riquadri"
        let byId = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        return view.slots.compactMap { byId[$0] }
    }

    func chooseView(_ id: String) {
        guard availableViews.contains(where: { $0.id == id }) else { return }
        selectedViewId = id
        UserDefaults.standard.set(id, forKey: "nvr-view-id")
        Task { await refreshCameras() }
    }

    func connect(address proposed: String, key proposedKey: String) async throws {
        let candidates = try Self.candidateAddresses(proposed)
        let secret = proposedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw NvrError(message: "Inserisci il codice delle app mostrato su Home Assistant") }
        var selected: URL?
        var response: CameraListResponse?
        var wrongKey = false
        var lastError = ""
        for candidate in candidates {
            do {
                response = try await fetch("/eacnvr/cameras", base: candidate, key: secret, timeout: 8)
                selected = candidate
                break
            } catch {
                lastError = error.localizedDescription
                if lastError.contains("Codice NVR errato") { wrongKey = true }
            }
        }
        guard let parsed = selected, let response else {
            if wrongKey { throw NvrError(message: "Codice delle app errato. Copialo dalle impostazioni dell'add-on EAC Vision.") }
            throw NvrError(message: "Servizio video non raggiungibile. Controlla in HA → EAC Vision → Rete che la porta 8766 (senza AI) o 8767 (AI) sia pubblicata. Con Tailscale prova prima l'indirizzo /eacnvr/info in Safari. Dettaglio: \(lastError)")
        }
        let views: [NvrView] = (try? await fetch("/eacnvr/views", base: parsed, key: secret)) ?? []
        address = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = parsed
        key = secret
        KeyStore.save(secret)
        UserDefaults.standard.set(address, forKey: "nvr-address")
        UserDefaults.standard.set(parsed.absoluteString, forKey: "nvr-base-url")
        cameras = selectView(response.cams, from: views)
        name = response.name
        error = ""
        connected = true
    }

    func refreshCameras() async {
        do {
            let response: CameraListResponse = try await fetch("/eacnvr/cameras")
            let views: [NvrView] = (try? await fetch("/eacnvr/views")) ?? []
            cameras = selectView(response.cams, from: views)
            name = response.name
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    func days(for camera: NvrCamera) async throws -> [NvrDay] {
        try await fetch("/eacnvr/days", query: [URLQueryItem(name: "cam", value: camera.id)])
    }

    func segments(for camera: NvrCamera, day: String) async throws -> [NvrSegment] {
        try await fetch("/eacnvr/segments", query: [URLQueryItem(name: "cam", value: camera.id), URLQueryItem(name: "day", value: day)])
    }

    func events() async throws -> [NvrEvent] {
        try await fetch("/eacnvr/events", query: [URLQueryItem(name: "limit", value: "100")])
    }

    func events(for camera: NvrCamera, day: String) async throws -> [NvrEvent] {
        try await fetch("/eacnvr/events", query: [URLQueryItem(name: "cam", value: camera.id),
                                                  URLQueryItem(name: "day", value: day),
                                                  URLQueryItem(name: "limit", value: "500")])
    }

    private func control(_ path: String, query: [URLQueryItem]) async throws {
        guard let address = url(path, query: query) else { throw NvrError(message: "NVR non configurato") }
        var request = URLRequest(url: address)
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NvrError(message: "Comando telecamera non riuscito")
        }
    }

    func ezvizMove(camera: NvrCamera, direction: String) async throws {
        guard camera.ezPtz == true, ["up", "down", "left", "right"].contains(direction) else {
            throw NvrError(message: "PTZ EZVIZ non disponibile")
        }
        let query = [URLQueryItem(name: "cam", value: camera.id), URLQueryItem(name: "dir", value: direction)]
        try await control("/eacnvr/ptz", query: query + [URLQueryItem(name: "action", value: "start")])
        try? await Task.sleep(for: .milliseconds(350))
        try await control("/eacnvr/ptz", query: query + [URLQueryItem(name: "action", value: "stop")])
    }

    func ezvizSiren(camera: NvrCamera, enabled: Bool) async throws {
        guard camera.ezSiren == true else { throw NvrError(message: "Sirena EZVIZ non disponibile") }
        try await control("/eacnvr/siren", query: [URLQueryItem(name: "cam", value: camera.id),
                                                  URLQueryItem(name: "on", value: enabled ? "1" : "0")])
    }

    func notifySettings() async throws -> NotifySettings { try await fetch("/eacnvr/notify") }

    func saveNotify(target: String, enabled: Bool, labels: [String]) async throws -> NotifySettings {
        try await post("/eacnvr/notify", body: ["target": target, "enabled": enabled, "labels": labels])
    }

    func testNotify(target: String) async throws {
        struct Sent: Decodable { let sent: Bool }
        let result: Sent = try await post("/eacnvr/notify-test", body: ["target": target])
        guard result.sent else { throw NvrError(message: "Notifica non inviata") }
    }
}
