import Foundation

struct BootstrapResponse: Decodable {
    let ok: Bool
    let api: Int?
    let authenticated: Bool?
    let csrf: String?
    let storeVersion: Int?
    let roomCount: Int?
    let unclearableRoom: String?
    let maxMessageChars: Int?
    let kdf: KDFConfig?
    let cipher: CipherConfig?

    enum CodingKeys: String, CodingKey {
        case ok, api, authenticated, csrf, kdf, cipher
        case storeVersion = "store_version"
        case roomCount = "room_count"
        case unclearableRoom = "unclearable_room"
        case maxMessageChars = "max_message_chars"
    }
}

struct KDFConfig: Decodable {
    let name: String
    let hash: String
    let saltB64: String
    let iterations: Int

    enum CodingKeys: String, CodingKey {
        case name, hash, iterations
        case saltB64 = "salt_b64"
    }
}

struct CipherConfig: Decodable {
    let version: Int
    let name: String
    let counterBits: Int

    enum CodingKeys: String, CodingKey {
        case version, name
        case counterBits = "counter_bits"
    }
}

struct RoomsResponse: Decodable {
    let ok: Bool
    let rooms: [String: Int]
}

struct ServerMessage: Decodable, Hashable {
    let m: String
    let u: String
    let d: String
}

struct HistoryResponse: Decodable {
    let ok: Bool
    let m: [ServerMessage]
}

struct BasicResponse: Decodable {
    let ok: Bool
    let duplicate: Bool?
}

struct APIErrorResponse: Decodable {
    let ok: Bool?
    let error: String?
    let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case ok, error
        case retryAfter = "retry_after"
    }
}

struct RoomItem: Identifiable, Hashable {
    let number: Int
    let count: Int
    var id: String { "room\(number)" }
    var title: String { "Room \(number)" }
}

struct DisplayMessage: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let mine: Bool
    let readable: Bool
}
