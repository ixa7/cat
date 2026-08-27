import Foundation
import Security
import CommonCrypto
import CryptoKit

struct ChatCrypto {
    enum CryptoError: LocalizedError {
        case invalidSalt
        case derivationFailed
        case invalidPayload
        case cryptorFailed(CCCryptorStatus)
        case unsupportedVersion
        case legacyAuthenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidSalt: return "Sel cryptographique invalide."
            case .derivationFailed: return "Dérivation de clé impossible."
            case .invalidPayload: return "Payload chiffré invalide."
            case let .cryptorFailed(status): return "Erreur AES-CTR (\(status))."
            case .unsupportedVersion: return "Version de message non supportée."
            case .legacyAuthenticationFailed: return "Ancien message illisible ou clé incorrecte."
            }
        }
    }

    private let key: Data
    private let legacyKey: Data

    init(passphrase: String, kdf: KDFConfig) throws {
        guard kdf.name.uppercased() == "PBKDF2",
              kdf.hash.uppercased() == "SHA-256",
              kdf.iterations >= 100_000,
              let salt = Data(base64Encoded: kdf.saltB64) else {
            throw CryptoError.invalidSalt
        }

        key = try Self.pbkdf2SHA256(
            password: passphrase,
            salt: salt,
            iterations: kdf.iterations,
            keyLength: 32
        )

        legacyKey = try Self.pbkdf2SHA256(
            password: passphrase,
            salt: Data("voilaxa-chat-v5|global-key".utf8),
            iterations: 180_000,
            keyLength: 32
        )
    }

    func encryptMessage(pseudo: String, text: String) throws -> String {
        let pseudoCounter = Self.randomCounter()
        let textCounter = Self.randomCounter()
        let pseudoCipher = try aesCTR(Data(pseudo.utf8), counter: pseudoCounter)
        let textCipher = try aesCTR(Data(text.utf8), counter: textCounter)

        let object: [String: String] = [
            "v": "6",
            "pi": pseudoCounter.base64EncodedString(),
            "pc": pseudoCipher.base64EncodedString(),
            "ti": textCounter.base64EncodedString(),
            "tc": textCipher.base64EncodedString()
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let string = String(data: data, encoding: .utf8) else { throw CryptoError.invalidPayload }
        return string
    }

    func decryptMessage(roomID: String, payload: String) throws -> (pseudo: String, text: String) {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["v"] as? String else {
            throw CryptoError.invalidPayload
        }

        if version == "6" {
            guard let pi = object["pi"] as? String,
                  let pc = object["pc"] as? String,
                  let ti = object["ti"] as? String,
                  let tc = object["tc"] as? String,
                  let pseudoCounter = Data(base64Encoded: pi), pseudoCounter.count == 16,
                  let pseudoCipher = Data(base64Encoded: pc),
                  let textCounter = Data(base64Encoded: ti), textCounter.count == 16,
                  let textCipher = Data(base64Encoded: tc) else {
                throw CryptoError.invalidPayload
            }

            let pseudoBytes = try aesCTR(pseudoCipher, counter: pseudoCounter)
            let textBytes = try aesCTR(textCipher, counter: textCounter)
            return (
                Self.visibleText(pseudoBytes, fallback: "auteur-brouille"),
                Self.visibleText(textBytes, fallback: "message-brouille")
            )
        }

        if version == "5" {
            guard let iv64 = object["i"] as? String,
                  let ct64 = object["c"] as? String,
                  let iv = Data(base64Encoded: iv64), iv.count == 12,
                  let combined = Data(base64Encoded: ct64), combined.count >= 16 else {
                throw CryptoError.invalidPayload
            }

            let ciphertext = combined.dropLast(16)
            let tag = combined.suffix(16)
            do {
                let nonce = try AES.GCM.Nonce(data: iv)
                let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
                let plaintext = try AES.GCM.open(
                    box,
                    using: SymmetricKey(data: legacyKey),
                    authenticating: Data("voilaxa-chat-v5|room|\(roomID)".utf8)
                )
                guard let decoded = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
                    throw CryptoError.invalidPayload
                }
                return (decoded["p"] as? String ?? "", decoded["t"] as? String ?? "")
            } catch {
                throw CryptoError.legacyAuthenticationFailed
            }
        }

        throw CryptoError.unsupportedVersion
    }

    private func aesCTR(_ input: Data, counter: Data) throws -> Data {
        guard counter.count == kCCBlockSizeAES128 else { throw CryptoError.invalidPayload }
        var cryptor: CCCryptorRef?

        let createStatus: CCCryptorStatus = key.withUnsafeBytes { keyBuffer in
            counter.withUnsafeBytes { counterBuffer in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    counterBuffer.baseAddress,
                    keyBuffer.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }
        guard createStatus == kCCSuccess, let cryptor else { throw CryptoError.cryptorFailed(createStatus) }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let updateStatus: CCCryptorStatus = output.withUnsafeMutableBytes { outBuffer in
            input.withUnsafeBytes { inBuffer in
                CCCryptorUpdate(
                    cryptor,
                    inBuffer.baseAddress,
                    input.count,
                    outBuffer.baseAddress,
                    // Taille lue sur le tampon et non sur « output » : accéder à
                    // output.count ici serait un accès concurrent à la variable
                    // dont la fermeture détient déjà l'accès exclusif.
                    outBuffer.count,
                    &moved
                )
            }
        }
        guard updateStatus == kCCSuccess else { throw CryptoError.cryptorFailed(updateStatus) }
        output.count = moved
        return output
    }

    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        let passwordBytes = Array(password.utf8)
        var derived = Data(count: keyLength)
        let status: Int32 = derived.withUnsafeMutableBytes { outputBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBytes.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordBytes.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.derivationFailed }
        return derived
    }

    private static func randomCounter() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
        return Data(bytes)
    }

    private static func visibleText(_ data: Data, fallback: String) -> String {
        var text = String(decoding: data, as: UTF8.self)
        let scalars = text.unicodeScalars.map { scalar -> String in
            let v = scalar.value
            if (v <= 8) || v == 11 || v == 12 || (v >= 14 && v <= 31) || v == 127 {
                return "�"
            }
            return String(scalar)
        }
        text = scalars.joined()
        if text.isEmpty {
            let hex = data.prefix(24).map { String(format: "%02x", $0) }.joined()
            return fallback + "-" + (hex.isEmpty ? "vide" : hex)
        }
        return text
    }
}
