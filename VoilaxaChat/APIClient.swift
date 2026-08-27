import Foundation

final class APIClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case http(Int, String)
        case malformedResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Adresse du serveur invalide."
            case let .http(code, message):
                return "HTTP \(code) : \(message)"
            case .malformedResponse:
                return "Réponse serveur invalide."
            case let .server(message):
                return message
            }
        }
    }

    private let endpoint: URL
    private let session: URLSession
    private var csrf = ""

    init(endpoint: URL) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func close() {
        session.invalidateAndCancel()
        csrf = ""
    }

    func bootstrap() async throws -> BootstrapResponse {
        let response: BootstrapResponse = try await post(action: "mobile_bootstrap", fields: [:], includeCSRF: false)
        if let value = response.csrf { csrf = value }
        return response
    }

    func login(password: String) async throws -> BootstrapResponse {
        let response: BootstrapResponse = try await post(
            action: "mobile_login",
            fields: ["access_password": password],
            includeCSRF: true
        )
        if let value = response.csrf { csrf = value }
        return response
    }

    func logout() async {
        _ = try? await postRaw(action: "mobile_logout", fields: [:], includeCSRF: true)
        close()
    }

    func rooms() async throws -> RoomsResponse {
        try await post(action: "rooms", fields: [:], includeCSRF: true)
    }

    func history(room: String) async throws -> HistoryResponse {
        try await post(action: "history", fields: ["r": room], includeCSRF: true)
    }

    func send(room: String, userID: String, messageID: String, payload: String) async throws -> BasicResponse {
        try await post(action: "send", fields: [
            "r": room,
            "u": userID,
            "m": messageID,
            "d": payload
        ], includeCSRF: true)
    }

    func clear(room: String) async throws -> BasicResponse {
        try await post(action: "clear", fields: ["r": room], includeCSRF: true)
    }

    private func post<T: Decodable>(action: String, fields: [String: String], includeCSRF: Bool) async throws -> T {
        let data = try await postRaw(action: action, fields: fields, includeCSRF: includeCSRF)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError.malformedResponse
        }
    }

    private func postRaw(action: String, fields: [String: String], includeCSRF: Bool) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        var form = fields
        form["a"] = action
        if includeCSRF { form["csrf"] = csrf }
        request.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.malformedResponse
        }

        if !(200...299).contains(http.statusCode) {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = apiError.error {
                throw ClientError.server(Self.friendlyError(message, retryAfter: apiError.retryAfter))
            }
            let body = String(data: data, encoding: .utf8) ?? "Erreur serveur"
            throw ClientError.http(http.statusCode, body)
        }

        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           apiError.ok == false,
           let message = apiError.error {
            throw ClientError.server(Self.friendlyError(message, retryAfter: apiError.retryAfter))
        }

        return data
    }

    private static func formEncode(_ values: [String: String]) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        return values
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private static func friendlyError(_ value: String, retryAfter: Int?) -> String {
        switch value {
        case "bad_access_password": return "Mot de passe d’accès incorrect."
        case "access_password_not_configured": return "Le mot de passe d’accès serveur n’est pas configuré."
        case "unauthorized": return "Session expirée."
        case "csrf": return "Session de sécurité invalide."
        case "bad_room": return "Room invalide."
        case "bad_user": return "Identifiant utilisateur invalide."
        case "bad_mid": return "Identifiant de message invalide."
        case "bad_payload": return "Message chiffré rejeté par le serveur."
        case "room_clear_forbidden": return "Cette room ne peut pas être vidée."
        case "rate_limited":
            if let seconds = retryAfter { return "Trop de tentatives. Réessaie dans environ \(seconds) s." }
            return "Trop d’actions. Réessaie plus tard."
        default: return value
        }
    }
}
