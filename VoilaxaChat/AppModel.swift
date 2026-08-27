import Foundation
import Security

@MainActor
final class AppModel: ObservableObject {
    // Le serveur est volontairement fixe : l'utilisateur ne peut pas le modifier.
    private static let endpoint = URL(string: "https://voilaxa.com/chat.php")!

    @Published var accessPassword = ""
    @Published var pseudoInput = ""
    @Published var encryptionPassphrase = ""
    @Published var rooms: [RoomItem] = []
    @Published var messages: [DisplayMessage] = []
    @Published var currentRoom: RoomItem?
    @Published var messageDraft = ""
    @Published var errorMessage = ""
    @Published var statusMessage = ""
    @Published var busy = false
    @Published private(set) var accessAuthenticated = false
    @Published private(set) var authenticated = false

    private var api: APIClient?
    private var crypto: ChatCrypto?
    private var pendingKDF: KDFConfig?
    private var pseudo = ""
    private var userID = ""
    private var roomCount = 11
    private var unclearableRoom = "room11"
    private var maxMessageChars = 4000
    private var pollTask: Task<Void, Never>?

    var canClearCurrentRoom: Bool {
        guard let currentRoom else { return false }
        return currentRoom.id != unclearableRoom
    }

    /// Étape 1 : mot de passe qui protège chat.php et ses API.
    func loginAccess() async {
        guard !busy else { return }
        errorMessage = ""
        statusMessage = ""

        guard !accessPassword.isEmpty else {
            errorMessage = "Mot de passe d’accès requis."
            return
        }

        busy = true
        defer { busy = false }

        let client = APIClient(endpoint: Self.endpoint)
        do {
            let bootstrap = try await client.bootstrap()
            let login = try await client.login(password: accessPassword)
            guard login.authenticated == true,
                  let kdf = login.kdf ?? bootstrap.kdf else {
                throw APIClient.ClientError.malformedResponse
            }

            api?.close()
            api = client
            pendingKDF = kdf
            roomCount = login.roomCount ?? bootstrap.roomCount ?? 11
            unclearableRoom = login.unclearableRoom ?? bootstrap.unclearableRoom ?? "room11"
            maxMessageChars = login.maxMessageChars ?? bootstrap.maxMessageChars ?? 4000
            accessAuthenticated = true

            // Le mot de passe d'accès n'a plus besoin de rester dans le modèle.
            accessPassword = ""
            errorMessage = ""
            statusMessage = ""
        } catch {
            client.close()
            errorMessage = error.localizedDescription
        }
    }

    /// Étape 2 : exactement le principe de la page web "Pseudo + Clé".
    /// La clé de chiffrement est dérivée localement et n'est jamais envoyée à PHP.
    func enterChat() async {
        guard !busy, accessAuthenticated, api != nil else { return }
        errorMessage = ""
        statusMessage = ""

        let trimmedPseudo = pseudoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPseudo.isEmpty else {
            errorMessage = "Pseudo requis."
            return
        }
        guard !encryptionPassphrase.isEmpty else {
            errorMessage = "Clé requise."
            return
        }
        guard let kdf = pendingKDF else {
            errorMessage = "Configuration cryptographique indisponible. Reconnecte-toi."
            return
        }

        busy = true
        defer { busy = false }

        do {
            let derivedCrypto = try ChatCrypto(passphrase: encryptionPassphrase, kdf: kdf)
            crypto = derivedCrypto
            pseudo = trimmedPseudo
            userID = Self.randomHex(bytes: 16)
            authenticated = true

            // La phrase secrète saisie n'est pas conservée après dérivation.
            encryptionPassphrase = ""
            statusMessage = ""
            await refreshRooms()
            startRoomPolling()
        } catch {
            crypto = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Bouton "Test" de l'écran Pseudo/Clé, analogue à la version web.
    func testConnection() async {
        guard !busy, accessAuthenticated, let api else { return }
        errorMessage = ""
        statusMessage = "Test en cours..."
        busy = true
        defer { busy = false }

        do {
            _ = try await api.rooms()
            if encryptionPassphrase.isEmpty {
                statusMessage = "OK : HTTPS + API PHP accessibles."
            } else if let kdf = pendingKDF {
                _ = try ChatCrypto(passphrase: encryptionPassphrase, kdf: kdf)
                statusMessage = "OK : HTTPS + API PHP + chiffrement local."
            } else {
                statusMessage = "OK : HTTPS + API PHP accessibles."
            }
        } catch {
            statusMessage = ""
            errorMessage = error.localizedDescription
        }
    }

    func refreshRooms() async {
        guard authenticated, let api else { return }
        do {
            let result = try await api.rooms()
            rooms = (1...roomCount).map { i in
                RoomItem(number: i, count: result.rooms["room\(i)"] ?? 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openRoom(_ room: RoomItem) async {
        currentRoom = room
        messages = []
        pollTask?.cancel()
        await loadMessages()
        startMessagePolling()
    }

    func closeRoom() async {
        pollTask?.cancel()
        currentRoom = nil
        messages = []
        await refreshRooms()
        startRoomPolling()
    }

    func loadMessages() async {
        guard authenticated, let api, let crypto, let room = currentRoom else { return }
        do {
            let history = try await api.history(room: room.id)
            messages = history.m.map { item in
                do {
                    let clear = try crypto.decryptMessage(roomID: room.id, payload: item.d)
                    return DisplayMessage(
                        id: item.m,
                        author: clear.pseudo.isEmpty ? "????" : clear.pseudo,
                        text: clear.text,
                        mine: item.u == userID || clear.pseudo == pseudo,
                        readable: true
                    )
                } catch {
                    return DisplayMessage(
                        id: item.m,
                        author: String(item.u.prefix(12)),
                        text: "ancien message illisible",
                        mine: item.u == userID,
                        readable: false
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage() async {
        guard authenticated, let api, let crypto, let room = currentRoom else { return }
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= maxMessageChars else {
            errorMessage = "Message trop long : maximum \(maxMessageChars) caractères."
            return
        }

        messageDraft = ""
        do {
            let payload = try crypto.encryptMessage(pseudo: pseudo, text: text)
            _ = try await api.send(
                room: room.id,
                userID: userID,
                messageID: Self.randomHex(bytes: 16),
                payload: payload
            )
            await loadMessages()
        } catch {
            messageDraft = text
            errorMessage = error.localizedDescription
        }
    }

    func clearCurrentRoom() async {
        guard canClearCurrentRoom, let room = currentRoom, let api else { return }
        do {
            _ = try await api.clear(room: room.id)
            await loadMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Quitter depuis les rooms : détruit aussi la session d'accès côté PHP.
    func logout() async {
        pollTask?.cancel()
        if let api { await api.logout() }
        clearSensitiveState()
    }

    /// Quitter depuis l'écran Pseudo/Clé avant d'entrer dans les rooms.
    func cancelAccessSession() async {
        pollTask?.cancel()
        if let api { await api.logout() }
        clearSensitiveState()
    }

    /// En arrière-plan, on oublie immédiatement session, clé dérivée et contenus clairs.
    func lockImmediately() {
        pollTask?.cancel()
        api?.close()
        clearSensitiveState()
    }

    private func clearSensitiveState() {
        api = nil
        crypto = nil
        pendingKDF = nil
        pseudo = ""
        userID = ""
        accessPassword = ""
        encryptionPassphrase = ""
        pseudoInput = ""
        messageDraft = ""
        messages = []
        rooms = []
        currentRoom = nil
        accessAuthenticated = false
        authenticated = false
        errorMessage = ""
        statusMessage = ""
    }

    private func startRoomPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshRooms()
            }
        }
    }

    private func startMessagePolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.loadMessages()
            }
        }
    }

    private static func randomHex(bytes: Int) -> String {
        var data = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, data.count, &data)
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
