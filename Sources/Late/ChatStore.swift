import Foundation

struct ChatStore {
    private let fileName = "chats.json"

    func load() -> [ChatThread] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ChatThread].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ chats: [ChatThread]) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(chats)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save chats: \(error.localizedDescription)")
        }
    }

    private var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("Late", isDirectory: true)
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }
}
