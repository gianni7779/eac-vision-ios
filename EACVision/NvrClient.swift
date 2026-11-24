import Foundation
import Security
import SwiftUI

struct NvrCamera: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let recorded: Bool?
    let recording: Bool?
}

struct CameraListResponse: Decodable {
    let name: String
    let cams: [NvrCamera]
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
    @Published var error = ""
    @Published var connected = false
    @Published var address = UserDefaults.standard.string(forKey: "nvr-address") ?? ""
    private(set) var baseURL: URL?
    private(set) var key = KeyStore.read()

    init() {
        if !address.isEmpty, !key.isEmpty, let url = try? Self.parseAddress(address) {
            baseURL = url
            connected = true
        }
    }

    static func parseAddress(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NvrError(message: "Inserisci l'indirizzo del registratore") }
        let value = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              scheme == "http" || scheme == "https" else {
            throw NvrError(message: "Indirizzo non valido")
        }
        if components.port == 8123 { throw NvrError(message: "La porta 8123 di Home Assistant non è la porta NVR") }
        if scheme == "http" && !privateHost(host) {
            throw NvrError(message: "Per DuckDNS usa un proxy HTTPS; per Tailscale usa l'IP 100.x.y.z")
        }
        components.port = components.port ?? (scheme == "https" ? 443 : 8766)
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw NvrError(message: "Indirizzo non valido") }
        return url
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

    private func fetch<T: Decodable>(_ path: String, query: [URLQueryItem] = [], base: URL? = nil, key: String? = nil) async throws -> T {
        guard let address = url(path, query: query, base: base, key: key) else { throw NvrError(message: "NVR non configurato") }
        var request = URLRequest(url: address)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NvrError(message: "Risposta NVR non valida") }
        if http.statusCode == 403 { throw NvrError(message: "Codice NVR errato") }
        guard http.statusCode == 200 else { throw NvrError(message: "NVR: errore HTTP \(http.statusCode)") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func connect(address proposed: String, key proposedKey: String) async throws {
        let parsed = try Self.parseAddress(proposed)
        let secret = proposedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw NvrError(message: "Inserisci il codice delle app mostrato su Home Assistant") }
        let response: CameraListResponse = try await fetch("/eacnvr/cameras", base: parsed, key: secret)
        address = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = parsed
        key = secret
        KeyStore.save(secret)
        UserDefaults.standard.set(address, forKey: "nvr-address")
        cameras = response.cams
        name = response.name
        error = ""
        connected = true
    }

    func refreshCameras() async {
        do {
            let response: CameraListResponse = try await fetch("/eacnvr/cameras")
            cameras = response.cams
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
}
