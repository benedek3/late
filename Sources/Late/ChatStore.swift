import CryptoKit
import Foundation
import Security

struct ChatStore {
    private let plaintextFileName = "chats.json"
    private let legacyEncryptedFileName = "chats.enc.json"
    private let indexFileName = "chats.index.enc.json"
    private let threadsDirectoryName = "chats"
    private let encryptionVersion = 1
    private let keyByteCount = 32
    private let defaultIterations = 120_000

    var hasEncryptedStore: Bool {
        FileManager.default.fileExists(atPath: indexFileURL.path) ||
            FileManager.default.fileExists(atPath: legacyEncryptedFileURL.path)
    }

    var hasPlaintextStore: Bool {
        FileManager.default.fileExists(atPath: plaintextFileURL.path)
    }

    func loadPlaintext() -> [ChatThread] {
        guard let data = try? Data(contentsOf: plaintextFileURL) else { return [] }

        return decode([ChatThread].self, from: data) ?? []
    }

    func unlock(password: String) throws -> (chats: [ChatThread], key: SymmetricKey) {
        if FileManager.default.fileExists(atPath: indexFileURL.path) {
            let indexArchive = try readArchive(from: indexFileURL)
            let key = deriveKey(password: password, salt: indexArchive.saltData, iterations: indexArchive.iterations)
            let index = try decrypt(ChatIndex.self, from: indexArchive, using: key)
            return (metadataThreads(from: index.entries), key)
        }

        return try unlockLegacyStore(password: password)
    }

    @discardableResult
    func createEncryptedStore(chats: [ChatThread], password: String) throws -> SymmetricKey {
        let salt = randomData(byteCount: 16)
        let key = deriveKey(password: password, salt: salt, iterations: defaultIterations)
        try writePerThreadStore(chats: chats, key: key, salt: salt, iterations: defaultIterations)
        _ = try unlock(password: password)
        return key
    }

    func loadThread(id: UUID, key: SymmetricKey) throws -> ChatThread {
        let archive = try readArchive(from: threadFileURL(for: id))
        return try decrypt(ChatThread.self, from: archive, using: key)
    }

    func saveIndex(_ chats: [ChatThread], key: SymmetricKey) throws {
        let archive = try readIndexArchive()
        try writeIndex(chats: chats, key: key, salt: archive.saltData, iterations: archive.iterations)
    }

    func saveThread(_ chat: ChatThread, key: SymmetricKey) throws {
        let archive = try readIndexArchive()
        try writeEncryptedPayload(chat, to: threadFileURL(for: chat.id), key: key, salt: archive.saltData, iterations: archive.iterations)
    }

    func deleteThread(id: UUID) {
        try? FileManager.default.removeItem(at: threadFileURL(for: id))
    }

    func deletePlaintextStore() {
        try? FileManager.default.removeItem(at: plaintextFileURL)
    }

    private func unlockLegacyStore(password: String) throws -> (chats: [ChatThread], key: SymmetricKey) {
        let archive = try readArchive(from: legacyEncryptedFileURL)
        let key = deriveKey(password: password, salt: archive.saltData, iterations: archive.iterations)
        let chats = try decrypt([ChatThread].self, from: archive, using: key)

        try writePerThreadStore(chats: chats, key: key, salt: archive.saltData, iterations: archive.iterations)
        let migratedIndex = try readArchive(from: indexFileURL)
        _ = try decrypt(ChatIndex.self, from: migratedIndex, using: key)
        try? FileManager.default.removeItem(at: legacyEncryptedFileURL)

        return (metadataThreads(from: chats.map(ChatIndexEntry.init(chat:))), key)
    }

    private func writePerThreadStore(chats: [ChatThread], key: SymmetricKey, salt: Data, iterations: Int) throws {
        try FileManager.default.createDirectory(at: threadsDirectoryURL, withIntermediateDirectories: true)

        for chat in chats {
            try writeEncryptedPayload(chat, to: threadFileURL(for: chat.id), key: key, salt: salt, iterations: iterations)
        }

        try writeIndex(chats: chats, key: key, salt: salt, iterations: iterations)
    }

    private func writeIndex(chats: [ChatThread], key: SymmetricKey, salt: Data, iterations: Int) throws {
        let entries = chats.map(ChatIndexEntry.init(chat:)).sorted { $0.updatedAt > $1.updatedAt }
        try writeEncryptedPayload(ChatIndex(entries: entries), to: indexFileURL, key: key, salt: salt, iterations: iterations)
    }

    private func metadataThreads(from entries: [ChatIndexEntry]) -> [ChatThread] {
        entries.map { entry in
            ChatThread(
                id: entry.id,
                title: entry.title,
                messages: [],
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )
        }
    }

    private func decrypt<T: Decodable>(_ type: T.Type, from archive: EncryptedArchive, using key: SymmetricKey) throws -> T {
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: archive.nonceData),
            ciphertext: archive.ciphertextData,
            tag: archive.tagData
        )
        let data = try AES.GCM.open(sealedBox, using: key)

        guard let value = decode(T.self, from: data) else {
            throw StoreError.invalidPayload
        }

        return value
    }

    private func writeEncryptedPayload<T: Encodable>(_ payload: T, to url: URL, key: SymmetricKey, salt: Data, iterations: Int) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: threadsDirectoryURL, withIntermediateDirectories: true)

        let sealedBox = try AES.GCM.seal(encoded(payload), using: key)
        let archive = EncryptedArchive(
            version: encryptionVersion,
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: iterations,
            salt: salt.base64EncodedString(),
            cipher: "AES-256-GCM",
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )

        let data = try encoded(archive)
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    private func readArchive(from url: URL) throws -> EncryptedArchive {
        let data = try Data(contentsOf: url)
        guard let archive = decode(EncryptedArchive.self, from: data) else {
            throw StoreError.invalidArchive
        }

        return archive
    }

    private func readIndexArchive() throws -> EncryptedArchive {
        if FileManager.default.fileExists(atPath: indexFileURL.path) {
            return try readArchive(from: indexFileURL)
        }

        return EncryptedArchive(
            version: encryptionVersion,
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: defaultIterations,
            salt: randomData(byteCount: 16).base64EncodedString(),
            cipher: "AES-256-GCM",
            nonce: "",
            ciphertext: "",
            tag: ""
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func encoded<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
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

    private var plaintextFileURL: URL {
        directoryURL.appendingPathComponent(plaintextFileName)
    }

    private var legacyEncryptedFileURL: URL {
        directoryURL.appendingPathComponent(legacyEncryptedFileName)
    }

    private var indexFileURL: URL {
        directoryURL.appendingPathComponent(indexFileName)
    }

    private var threadsDirectoryURL: URL {
        directoryURL.appendingPathComponent(threadsDirectoryName, isDirectory: true)
    }

    private func threadFileURL(for id: UUID) -> URL {
        threadsDirectoryURL.appendingPathComponent("\(id.uuidString).enc.json")
    }
}

private struct ChatIndex: Codable {
    let entries: [ChatIndexEntry]
}

private struct ChatIndexEntry: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date

    init(chat: ChatThread) {
        self.id = chat.id
        self.title = chat.title
        self.createdAt = chat.createdAt
        self.updatedAt = chat.updatedAt
    }
}

private struct EncryptedArchive: Codable {
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
