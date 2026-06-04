import Foundation

struct OpenRouterClient {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func streamReply(
        apiKey: String,
        model: String,
        webSearchEnabled: Bool,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        onContentDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AssistantReply {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Late", forHTTPHeaderField: "X-Title")
        let sourceInstruction = webSearchEnabled
            ? " When web search is enabled, include a final Sources section with Markdown links for every source used."
            : ""
        let resolvedSystemPrompt = systemPrompt ?? "Format answers with clean Markdown. Use short paragraphs, blank lines between sections, proper numbered or bulleted lists, and fenced code blocks when useful. Never return dense run-on text.\(sourceInstruction)"
        let formattedMessages = [
            RequestMessage(
                role: "system",
                content: .text(resolvedSystemPrompt)
            )
        ] + messages.map { RequestMessage(role: $0.role.rawValue, content: RequestContent(message: $0)) }
        var plugins: [RequestPlugin] = []
        if webSearchEnabled {
            plugins.append(.web)
        }
        if messages.contains(where: { $0.attachments.contains(where: { $0.kind == .file }) }) {
            plugins.append(.fileParser)
        }

        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: formattedMessages,
                stream: true,
                plugins: plugins.isEmpty ? nil : plugins
            )
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }

            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
               let message = apiError.error?.message {
                throw OpenRouterClientError.api(message)
            }

            throw OpenRouterClientError.api("OpenRouter returned HTTP \(httpResponse.statusCode).")
        }

        var content = ""
        var sources: [ChatSource] = []

        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("data:") else { continue }

            let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(StreamingChatCompletionEnvelope.self, from: data)

            if let message = chunk.error?.message {
                throw OpenRouterClientError.api(message)
            }

            let delta = chunk.contentDelta
            if !delta.isEmpty {
                content += delta
                await onContentDelta(delta)
            }

            sources.append(contentsOf: chunk.sources)
            sources = Self.uniqueSources(sources)
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return AssistantReply(content: trimmedContent, sources: sources)
        }

        throw OpenRouterClientError.emptyResponse
    }

    fileprivate static func uniqueSources(_ sources: [ChatSource]) -> [ChatSource] {
        var seen = Set<String>()
        return sources.filter { source in
            guard !seen.contains(source.url) else { return false }
            seen.insert(source.url)
            return true
        }
    }
}

struct AssistantReply {
    let content: String
    let sources: [ChatSource]
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let stream: Bool
    let plugins: [RequestPlugin]?
}

private struct RequestMessage: Encodable {
    let role: String
    let content: RequestContent
}

private enum RequestContent: Encodable {
    case text(String)
    case parts([RequestContentPart])

    init(message: ChatMessage) {
        let imageParts = message.attachments
            .filter { $0.kind == .image }
            .map { RequestContentPart.imageURL($0.dataURL) }
        let fileParts = message.attachments
            .filter { $0.kind == .file }
            .map { RequestContentPart.file(filename: $0.name, dataURL: $0.dataURL) }
        let attachmentParts = imageParts + fileParts

        guard !attachmentParts.isEmpty else {
            self = .text(message.content)
            return
        }

        var parts: [RequestContentPart] = []
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            parts.append(.text(trimmedContent))
        }
        parts.append(contentsOf: attachmentParts)
        self = .parts(parts)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private enum RequestContentPart: Encodable {
    case text(String)
    case imageURL(String)
    case file(filename: String, dataURL: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case file
    }

    private enum ImageURLCodingKeys: String, CodingKey {
        case url
    }

    private enum FileCodingKeys: String, CodingKey {
        case filename
        case fileData = "file_data"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            var imageURL = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
            try imageURL.encode(url, forKey: .url)
        case .file(let filename, let dataURL):
            try container.encode("file", forKey: .type)
            var file = container.nestedContainer(keyedBy: FileCodingKeys.self, forKey: .file)
            try file.encode(filename, forKey: .filename)
            try file.encode(dataURL, forKey: .fileData)
        }
    }
}

private enum RequestPlugin: Encodable {
    case web
    case fileParser

    private enum CodingKeys: String, CodingKey {
        case id
        case pdf
    }

    private enum PDFCodingKeys: String, CodingKey {
        case engine
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .web:
            try container.encode("web", forKey: .id)
        case .fileParser:
            try container.encode("file-parser", forKey: .id)
            var pdf = container.nestedContainer(keyedBy: PDFCodingKeys.self, forKey: .pdf)
            try pdf.encode("cloudflare-ai", forKey: .engine)
        }
    }
}

private struct StreamingChatCompletionEnvelope: Decodable {
    let choices: [StreamingChoice]?
    let citations: [FlexibleCitation]?
    let error: APIError?

    var contentDelta: String {
        choices?.compactMap(\.delta?.content).joined() ?? ""
    }

    var sources: [ChatSource] {
        OpenRouterClient.uniqueSources(
            (choices?.flatMap { $0.delta?.sources ?? [] } ?? []) +
            (citations?.map(\.source) ?? [])
        )
    }
}

private struct StreamingChoice: Decodable {
    let delta: StreamingDelta?
}

private struct StreamingDelta: Decodable {
    let content: String?
    let annotations: [ResponseAnnotation]?
    let citations: [FlexibleCitation]?

    var sources: [ChatSource] {
        (annotations?.compactMap(\.source) ?? []) + (citations?.map(\.source) ?? [])
    }
}

private struct ResponseAnnotation: Decodable {
    let title: String?
    let url: String?
    let urlCitation: URLCitation?

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case urlCitation = "url_citation"
    }

    var source: ChatSource? {
        if let urlCitation {
            return ChatSource(title: urlCitation.title, url: urlCitation.url)
        }

        guard let url else { return nil }
        return ChatSource(title: title, url: url)
    }
}

private struct URLCitation: Decodable {
    let title: String?
    let url: String
}

private struct FlexibleCitation: Decodable {
    let source: ChatSource

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let url = try? container.decode(String.self) {
            self.source = ChatSource(title: nil, url: url)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(String.self, forKey: .url)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        self.source = ChatSource(title: title, url: url)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case url
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError?
}

private struct APIError: Decodable {
    let message: String?
}

enum OpenRouterClientError: LocalizedError {
    case invalidResponse
    case emptyResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response was not valid."
        case .emptyResponse:
            return "The model returned an empty response."
        case .api(let message):
            return message
        }
    }
}
