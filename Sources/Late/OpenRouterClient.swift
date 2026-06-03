import Foundation

struct OpenRouterClient {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func fetchReply(apiKey: String, model: String, webSearchEnabled: Bool, messages: [ChatMessage]) async throws -> AssistantReply {
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
                plugins: webSearchEnabled ? [RequestPlugin(id: "web")] : nil
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
               let message = apiError.error?.message {
                throw OpenRouterClientError.api(message)
            }

            throw OpenRouterClientError.api("OpenRouter returned HTTP \(httpResponse.statusCode).")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionEnvelope.self, from: data)
        if let reply = decoded.reply, !reply.content.isEmpty {
            return reply
        }

        throw OpenRouterClientError.emptyResponse
    }
}

struct AssistantReply {
    let content: String
    let sources: [ChatSource]
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let plugins: [RequestPlugin]?
}

private struct RequestMessage: Encodable {
    let role: String
    let content: String
}

private struct RequestPlugin: Encodable {
    let id: String
}

private struct ChatCompletionEnvelope: Decodable {
    let choices: [Choice]
    let citations: [FlexibleCitation]?

    var reply: AssistantReply? {
        guard let message = choices.first?.message else { return nil }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return AssistantReply(
            content: text,
            sources: Self.uniqueSources(message.sources + (citations?.map(\.source) ?? []))
        )
    }

    private static func uniqueSources(_ sources: [ChatSource]) -> [ChatSource] {
        var seen = Set<String>()
        return sources.filter { source in
            guard !seen.contains(source.url) else { return false }
            seen.insert(source.url)
            return true
        }
    }
}

private struct Choice: Decodable {
    let message: ResponseMessage
}

private struct ResponseMessage: Decodable {
    let content: String
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
