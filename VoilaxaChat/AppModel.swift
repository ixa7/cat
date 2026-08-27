import Foundation
import Security

@MainActor
final class AppModel: ObservableObject {
    @Published var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://example.com/chat.php"
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
    @Published private(set) var authenticated = false

    private var api: APIClient?
    private var crypto: ChatCrypto?
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

    func connect() async {
        guard !busy else { return }
        errorMessage = ""
        statusMessage = ""

        let trimmedPseudo = pseudoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPseudo.isEmpty, !encryptionPassphrase.isEmpty, !accessPassword.isEmpty else {
            errorMessage = "Serveur, mot de passe d’accès, pseudo et clé de chiffrement sont requis."
            return
        }
        guard let url = URL(string: serverURL), url.scheme?.lowercased() == "https" else {
            errorMessage = "Utilise une adresse HTTPS complète vers chat.php."
            return
        }

        busy = true
        defer { busy = false }

        do {
            let client = APIClient(endpoint: url)
            let bootstrap = try await client.bootstrap()
            guard let kdf = bootstrap.kdf else { throw APIClient.ClientError.malformedResponse }

            let login = try await client.login(password: accessPassword)
            guard login.authenticated == true, let loginKDF = login.kdf ?? bootstrap.kdf else {
                throw APIClient.ClientError.malformedResponse
            }

            let derivedCrypto = try ChatCrypto(passphrase: encryptionPassphrase, kdf: loginKDF)
            api = client
            crypto = derivedCrypto
            pseudo = trimmedPseudo
            userID = Self.randomHex(bytes: 16)
            roomCount = login.roomCount ?? bootstrap.roomCount ?? 11
            unclearableRoom = login.unclearableRoom ?? bootstrap.unclearableRoom ?? "room11"
            maxMessageChars = login.maxMessageChars ?? bootstrap.maxMessageChars ?? 4000
            authenticated = true

            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            accessPassword = ""
            encryptionPassphrase = ""
            statusMessage = "Connecté. La clé de chiffrement reste en mémoire uniquement."
            await refreshRooms()
            startRoomPolling()
        } catch {
            api?.close()
            api = nil
            crypto = nil
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

    func logout() async {
        pollTask?.cancel()
        if let api { await api.logout() }
        clearSensitiveState()
    }

    func lockImmediately() {
        pollTask?.cancel()
        api?.close()
        clearSensitiveState()
    }

    private func clearSensitiveState() {
        api = nil
        crypto = nil
        pseudo = ""
        userID = ""
        accessPassword = ""
        encryptionPassphrase = ""
        messageDraft = ""
        messages = []
        rooms = []
        currentRoom = nil
        authenticated = false
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
