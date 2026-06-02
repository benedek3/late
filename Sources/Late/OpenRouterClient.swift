import Foundation

struct OpenRouterClient {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func fetchReply(apiKey: String, model: String, webSearchEnabled: Bool, messages: [ChatMessage]) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Late", forHTTPHeaderField: "X-Title")
        let formattedMessages = [
            RequestMessage(
                role: "system",
                content: "Format answers with clean Markdown. Use short paragraphs, blank lines between sections, proper numbered or bulleted lists, and fenced code blocks when useful. Never return dense run-on text."
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
        if let text = decoded.replyText, !text.isEmpty {
            return text
        }

        throw OpenRouterClientError.emptyResponse
    }
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

    var replyText: String? {
        let text = choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct Choice: Decodable {
    let message: ResponseMessage
}

private struct ResponseMessage: Decodable {
    let content: String
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
