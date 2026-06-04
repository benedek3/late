import CryptoKit
import Foundation
import Security

struct ChatStore {
    private let fileName = "chats.json"
    private let encryptedFileName = "chats.enc.json"
    private let encryptionVersion = 1
    private let keyByteCount = 32
    private let defaultIterations = 120_000

    var hasEncryptedStore: Bool {
        FileManager.default.fileExists(atPath: encryptedFileURL.path)
    }

    var hasPlaintextStore: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func loadPlaintext() -> [ChatThread] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        return decodeChats(from: data) ?? []
    }

    func unlock(password: String) throws -> (chats: [ChatThread], key: SymmetricKey) {
        let archive = try readArchive()
        let key = deriveKey(password: password, salt: archive.saltData, iterations: archive.iterations)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: archive.nonceData),
            ciphertext: archive.ciphertextData,
            tag: archive.tagData
        )
        let data = try AES.GCM.open(sealedBox, using: key)

        guard let chats = decodeChats(from: data) else {
            throw StoreError.invalidPayload
        }

        return (chats, key)
    }

    @discardableResult
    func createEncryptedStore(chats: [ChatThread], password: String) throws -> SymmetricKey {
        let salt = randomData(byteCount: 16)
        let key = deriveKey(password: password, salt: salt, iterations: defaultIterations)
        try writeEncrypted(chats: chats, key: key, salt: salt, iterations: defaultIterations)
        _ = try unlock(password: password)
        return key
    }

    func saveEncrypted(_ chats: [ChatThread], key: SymmetricKey) throws {
        let archive = try readArchive()
        try writeEncrypted(chats: chats, key: key, salt: archive.saltData, iterations: archive.iterations)
    }

    func deletePlaintextStore() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func decodeChats(from data: Data) -> [ChatThread]? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ChatThread].self, from: data)
        } catch {
            return nil
        }
    }

    private func encodedChats(_ chats: [ChatThread]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(chats)
    }

    private func readArchive() throws -> EncryptedChatArchive {
        let data = try Data(contentsOf: encryptedFileURL)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(EncryptedChatArchive.self, from: data)
        } catch {
            throw StoreError.invalidArchive
        }
    }

    private func writeEncrypted(chats: [ChatThread], key: SymmetricKey, salt: Data, iterations: Int) throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let sealedBox = try AES.GCM.seal(encodedChats(chats), using: key)
            let sealedNonce = Data(sealedBox.nonce)

            let archive = EncryptedChatArchive(
                version: encryptionVersion,
                kdf: "PBKDF2-HMAC-SHA256",
                iterations: iterations,
                salt: salt.base64EncodedString(),
                cipher: "AES-256-GCM",
                nonce: sealedNonce.base64EncodedString(),
                ciphertext: sealedBox.ciphertext.base64EncodedString(),
                tag: sealedBox.tag.base64EncodedString()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(archive)
            try data.write(to: encryptedFileURL, options: Data.WritingOptions.atomic)
        } catch {
            throw error
        }
    }

    private func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let derivedBytes = pbkdf2SHA256(password: passwordData, salt: salt, iterations: iterations, byteCount: keyByteCount)
        return SymmetricKey(data: derivedBytes)
    }

    private func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, byteCount: Int) -> Data {
        var derived = Data()
        let blockCount = Int(ceil(Double(byteCount) / Double(SHA256.byteCount)))

        for blockIndex in 1...blockCount {
            var blockSalt = salt
            blockSalt.append(UInt8((blockIndex >> 24) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 16) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 8) & 0xff))
            blockSalt.append(UInt8(blockIndex & 0xff))

            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: SymmetricKey(data: password)))
            var block = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: password)))
                    for offset in 0..<block.count {
                        block[offset] ^= u[offset]
                    }
                }
            }

            derived.append(block)
        }

        return Data(derived.prefix(byteCount))
    }

    private func randomData(byteCount: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes)
    }

    private var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("Late", isDirectory: true)
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    private var encryptedFileURL: URL {
        directoryURL.appendingPathComponent(encryptedFileName)
    }
}

private struct EncryptedChatArchive: Codable {
    let version: Int
    let kdf: String
    let iterations: Int
    let salt: String
    let cipher: String
    let nonce: String
    let ciphertext: String
    let tag: String

    var saltData: Data { Data(base64Encoded: salt) ?? Data() }
    var nonceData: Data { Data(base64Encoded: nonce) ?? Data() }
    var ciphertextData: Data { Data(base64Encoded: ciphertext) ?? Data() }
    var tagData: Data { Data(base64Encoded: tag) ?? Data() }
}

private enum StoreError: Error {
    case invalidArchive
    case invalidPayload
}
