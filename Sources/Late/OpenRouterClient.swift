import Foundation

struct OpenRouterClient {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func streamReply(apiKey: String, model: String, webSearchEnabled: Bool, messages: [ChatMessage], onContentDelta: @escaping @MainActor (String) -> Void) async throws -> AssistantReply {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Late", forHTTPHeaderField: "X-Title")
        let sourceInstruction = webSearchEnabled
            ? " When web search is enabled, include a final Sources section with Markdown links for every source used."
            : ""
        let formattedMessages = [
            RequestMessage(
                role: "system",
                content: "Format answers with clean Markdown. Use short paragraphs, blank lines between sections, proper numbered or bulleted lists, and fenced code blocks when useful. Never return dense run-on text.\(sourceInstruction)"
            )
        ] + messages.map { RequestMessage(role: $0.role.rawValue, content: $0.content) }

        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: formattedMessages,
                stream: true,
                plugins: webSearchEnabled ? [RequestPlugin(id: "web")] : nil
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
    let content: String
}

private struct RequestPlugin: Encodable {
    let id: String
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
