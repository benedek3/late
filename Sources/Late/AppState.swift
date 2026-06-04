import CryptoKit
import Foundation

struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AppearanceShortcut: String, CaseIterable, Identifiable {
    case optionTab
    case optionSpace
    case commandOptionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionTab:
            return "Option+Tab"
        case .optionSpace:
            return "Option+Space"
        case .commandOptionSpace:
            return "Command+Option+Space"
        case .commandShiftSpace:
            return "Command+Shift+Space"
        }
    }
}

extension Notification.Name {
    static let appearanceShortcutDidChange = Notification.Name("appearanceShortcutDidChange")
}

enum HistoryAccessState: Equatable {
    case setup
    case locked
    case unlocked
}

struct ChatSource: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String?
    let url: String

    init(id: UUID = UUID(), title: String?, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.url = try container.decode(String.self, forKey: .url)
    }
}

struct ChatAttachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image
        case file
    }

    let id: UUID
    let kind: Kind
    let name: String
    let mimeType: String
    let dataURL: String

    init(id: UUID = UUID(), kind: Kind, name: String, mimeType: String, dataURL: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.dataURL = dataURL
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    var sources: [ChatSource]
    var modelName: String?
    var attachments: [ChatAttachment]

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date(), sources: [ChatSource] = [], modelName: String? = nil, attachments: [ChatAttachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sources = sources
        self.modelName = modelName
        self.attachments = attachments
    }

    enum Role: String, Codable {
        case user
        case assistant
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case sources
        case modelName
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.sources = try container.decodeIfPresent([ChatSource].self, forKey: .sources) ?? []
        self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        self.attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }
}

struct ChatThread: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class AppState: ObservableObject {
    static let availableModels = [
        ModelOption(id: "openrouter/auto", name: "OpenRouter Auto"),
        ModelOption(id: "openai/gpt-5.5", name: "GPT-5.5"),
        ModelOption(id: "openai/gpt-5.4", name: "GPT-5.4"),
        ModelOption(id: "openai/gpt-5.4-mini", name: "GPT-5.4 Mini"),
        ModelOption(id: "openai/gpt-5.4-nano", name: "GPT-5.4 Nano"),
        ModelOption(id: "anthropic/claude-opus-4.8", name: "Claude Opus 4.8"),
        ModelOption(id: "anthropic/claude-sonnet-4.8", name: "Claude Sonnet 4.8")
    ]
    static let translationModelID = "openai/gpt-5.4-nano"
    static let translationModelName = "GPT-5.4 Nano"
    static let translationLanguages = [
        "English",
        "Hungarian",
        "Spanish",
        "French",
        "German",
        "Italian",
        "Portuguese",
        "Japanese",
        "Korean",
        "Chinese"
    ]

    @Published var isConfigured: Bool
    @Published var setupAPIKey = ""
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: selectedModelKey)
        }
    }
    @Published var selectedShortcut: AppearanceShortcut {
        didSet {
            UserDefaults.standard.set(selectedShortcut.rawValue, forKey: selectedShortcutKey)
            NotificationCenter.default.post(name: .appearanceShortcutDidChange, object: nil)
        }
    }
    @Published var chats: [ChatThread] = []
    @Published var selectedChatID: UUID? {
        didSet {
            if let selectedChatID {
                UserDefaults.standard.set(selectedChatID.uuidString, forKey: selectedChatIDKey)
            }
        }
    }
    @Published var prompt = ""
    @Published var focusToken = 0
    @Published var isHistoryVisible = false
    @Published var historyAccessState: HistoryAccessState = .locked
    @Published var isWebSearchEnabled = false
    @Published var settingsAPIKey = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isTranslationMode = false
    @Published var translationInput = ""
    @Published var translationOutput = ""
    @Published var translationTargetLanguage = "English"

    private let keychain = KeychainStore()
    private let apiClient = OpenRouterClient()
    private let chatStore = ChatStore()
    private var historyEncryptionKey: SymmetricKey?
    private let selectedModelKey = "selected-model"
    private let selectedChatIDKey = "selected-chat-id"
    private let selectedShortcutKey = "selected-shortcut"

    var currentChat: ChatThread? {
        guard let selectedChatID else { return nil }
        return chats.first { $0.id == selectedChatID }
    }

    var currentMessages: [ChatMessage] {
        currentChat?.messages ?? []
    }

    var sortedChats: [ChatThread] {
        chats.sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedModelName: String {
        AppState.availableModels.first { $0.id == selectedModel }?.name ?? selectedModel
    }

    init() {
        let savedModel = UserDefaults.standard.string(forKey: selectedModelKey)
        self.selectedModel = AppState.availableModels.contains(where: { $0.id == savedModel })
            ? savedModel ?? AppState.availableModels[0].id
            : AppState.availableModels[0].id
        let savedShortcut = UserDefaults.standard.string(forKey: selectedShortcutKey)
        self.selectedShortcut = AppearanceShortcut(rawValue: savedShortcut ?? "") ?? .optionTab
        self.isConfigured = keychain.readAPIKey() != nil
        self.historyAccessState = chatStore.hasEncryptedStore ? .locked : .setup
    }

    func saveAPIKey() {
        let apiKey = setupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        if keychain.saveAPIKey(apiKey) {
            setupAPIKey = ""
            isConfigured = true
            errorMessage = nil
        } else {
            errorMessage = "Could not save the OpenRouter API key to Keychain."
        }
    }

    func saveSettingsAPIKey() {
        let apiKey = settingsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        if keychain.saveAPIKey(apiKey) {
            settingsAPIKey = ""
            isConfigured = true
            errorMessage = nil
        } else {
            errorMessage = "Could not save the OpenRouter API key to Keychain."
        }
    }

    func resetAPIKey() {
        keychain.deleteAPIKey()
        isConfigured = false
        setupAPIKey = ""
        errorMessage = nil
    }

    func unlockHistory(password: String) {
        guard !password.isEmpty else {
            errorMessage = "Enter your history password."
            return
        }

        do {
            let result = try chatStore.unlock(password: password)
            historyEncryptionKey = result.key
            chats = result.chats.isEmpty ? [ChatThread()] : result.chats
            selectInitialChat()
            historyAccessState = .unlocked
            errorMessage = nil
            focusPrompt()
        } catch {
            errorMessage = "Could not unlock chat history. Check the password."
        }
    }

    func createHistoryPassword(password: String, confirmation: String) {
        guard password.count >= 8 else {
            errorMessage = "Use at least 8 characters for the history password."
            return
        }

        guard password == confirmation else {
            errorMessage = "History passwords do not match."
            return
        }

        do {
            let migratedChats = chatStore.loadPlaintext()
            let initialChats = migratedChats.isEmpty ? [ChatThread()] : migratedChats
            let key = try chatStore.createEncryptedStore(chats: initialChats, password: password)
            chatStore.deletePlaintextStore()
            historyEncryptionKey = key
            chats = initialChats
            selectInitialChat()
            historyAccessState = .unlocked
            errorMessage = nil
            focusPrompt()
        } catch {
            errorMessage = "Could not create encrypted chat history."
        }
    }

    func startNewChat() {
        let chat = ChatThread()
        chats.append(chat)
        selectedChatID = chat.id
        prompt = ""
        errorMessage = nil
        saveChats()
    }

    func selectChat(_ chat: ChatThread) {
        selectedChatID = chat.id
        prompt = ""
        errorMessage = nil
    }

    func focusPrompt() {
        focusToken += 1
    }

    func toggleHistory() {
        isHistoryVisible.toggle()
    }

    func setHistoryVisible(_ isVisible: Bool) {
        isHistoryVisible = isVisible
    }

    func toggleTranslationMode() {
        isTranslationMode.toggle()
        errorMessage = nil
        focusPrompt()
    }

    func clearCurrentChat() {
        guard let index = selectedChatIndex else { return }
        chats[index].messages.removeAll()
        chats[index].title = "New Chat"
        chats[index].updatedAt = Date()
        errorMessage = nil
        saveChats()
    }

    func deleteChat(_ chat: ChatThread) {
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else { return }
        let wasSelected = selectedChatID == chat.id
        chats.remove(at: index)

        if chats.isEmpty {
            let newChat = ChatThread()
            chats.append(newChat)
            selectedChatID = newChat.id
        } else if wasSelected {
            selectedChatID = sortedChats.first?.id ?? chats.first?.id
        }

        errorMessage = nil
        saveChats()
    }

    func sendPrompt(attachments: [ChatAttachment] = []) async {
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty || !attachments.isEmpty, !isLoading else { return }
        guard let apiKey = keychain.readAPIKey(), !apiKey.isEmpty else {
            isConfigured = false
            return
        }

        errorMessage = nil
        prompt = ""
        isLoading = true
        ensureSelectedChat()
        guard let index = selectedChatIndex else {
            isLoading = false
            return
        }

        let messageContent = userPrompt.isEmpty ? "Uploaded attachment\(attachments.count == 1 ? "" : "s")" : userPrompt
        chats[index].messages.append(ChatMessage(role: .user, content: messageContent, attachments: attachments))
        chats[index].updatedAt = Date()

        if chats[index].title == "New Chat" {
            chats[index].title = Self.title(from: userPrompt)
        }

        let assistantMessageID = UUID()
        let responseModelName = selectedModelName
        chats[index].messages.append(ChatMessage(id: assistantMessageID, role: .assistant, content: "", modelName: responseModelName))

        let requestChatID = chats[index].id
        let requestMessages = chats[index].messages
        saveChats()

        do {
            let reply = try await apiClient.streamReply(
                apiKey: apiKey,
                model: selectedModel,
                webSearchEnabled: isWebSearchEnabled,
                messages: requestMessages.filter { $0.id != assistantMessageID },
                onContentDelta: { [weak self] delta in
                    guard let self,
                          let chatIndex = self.chats.firstIndex(where: { $0.id == requestChatID }),
                          let messageIndex = self.chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                        return
                    }

                    self.chats[chatIndex].messages[messageIndex].content += delta
                    self.chats[chatIndex].updatedAt = Date()
                }
            )
            if let chatIndex = chats.firstIndex(where: { $0.id == requestChatID }),
               let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) {
                chats[chatIndex].messages[messageIndex].content = reply.content
                chats[chatIndex].messages[messageIndex].sources = reply.sources
                chats[chatIndex].messages[messageIndex].modelName = responseModelName
                chats[chatIndex].updatedAt = Date()
                saveChats()
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                errorMessage = nil
                saveChats()
                isLoading = false
                return
            }

            errorMessage = error.localizedDescription
            if let chatIndex = chats.firstIndex(where: { $0.id == requestChatID }),
               let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }),
               chats[chatIndex].messages[messageIndex].content.isEmpty {
                chats[chatIndex].messages.remove(at: messageIndex)
            }
            saveChats()
        }

        isLoading = false
    }

    func retryResponse(id assistantMessageIDToRetry: UUID) async {
        guard !isLoading else { return }
        guard let apiKey = keychain.readAPIKey(), !apiKey.isEmpty else {
            isConfigured = false
            return
        }
        guard let index = selectedChatIndex,
              let retryIndex = chats[index].messages.firstIndex(where: { $0.id == assistantMessageIDToRetry && $0.role == .assistant }) else {
            return
        }

        let contextEndIndex = retryIndex - 1
        guard contextEndIndex >= 0,
              chats[index].messages[contextEndIndex].role == .user else {
            return
        }

        errorMessage = nil
        isLoading = true
        chats[index].messages.removeSubrange(retryIndex..<chats[index].messages.endIndex)
        chats[index].updatedAt = Date()

        let assistantMessageID = UUID()
        let responseModelName = selectedModelName
        chats[index].messages.append(ChatMessage(id: assistantMessageID, role: .assistant, content: "", modelName: responseModelName))

        let requestChatID = chats[index].id
        let requestMessages = chats[index].messages.filter { $0.id != assistantMessageID }
        saveChats()

        do {
            let reply = try await apiClient.streamReply(
                apiKey: apiKey,
                model: selectedModel,
                webSearchEnabled: isWebSearchEnabled,
                messages: requestMessages,
                onContentDelta: { [weak self] delta in
                    guard let self,
                          let chatIndex = self.chats.firstIndex(where: { $0.id == requestChatID }),
                          let messageIndex = self.chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
                        return
                    }

                    self.chats[chatIndex].messages[messageIndex].content += delta
                    self.chats[chatIndex].updatedAt = Date()
                }
            )
            if let chatIndex = chats.firstIndex(where: { $0.id == requestChatID }),
               let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) {
                chats[chatIndex].messages[messageIndex].content = reply.content
                chats[chatIndex].messages[messageIndex].sources = reply.sources
                chats[chatIndex].messages[messageIndex].modelName = responseModelName
                chats[chatIndex].updatedAt = Date()
                saveChats()
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                errorMessage = nil
                saveChats()
                isLoading = false
                return
            }

            errorMessage = error.localizedDescription
            if let chatIndex = chats.firstIndex(where: { $0.id == requestChatID }),
               let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == assistantMessageID }),
               chats[chatIndex].messages[messageIndex].content.isEmpty {
                chats[chatIndex].messages.remove(at: messageIndex)
            }
            saveChats()
        }

        isLoading = false
    }

    func translateText() async {
        let text = translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        guard let apiKey = keychain.readAPIKey(), !apiKey.isEmpty else {
            isConfigured = false
            return
        }

        errorMessage = nil
        translationOutput = ""
        isLoading = true

        do {
            let reply = try await apiClient.streamReply(
                apiKey: apiKey,
                model: Self.translationModelID,
                webSearchEnabled: false,
                messages: [ChatMessage(role: .user, content: text)],
                systemPrompt: Self.translationSystemPrompt(targetLanguage: translationTargetLanguage),
                onContentDelta: { [weak self] delta in
                    self?.translationOutput += delta
                }
            )
            translationOutput = reply.content
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                errorMessage = nil
                isLoading = false
                return
            }

            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private var selectedChatIndex: Array<ChatThread>.Index? {
        guard let selectedChatID else { return nil }
        return chats.firstIndex { $0.id == selectedChatID }
    }

    private func ensureSelectedChat() {
        guard selectedChatIndex == nil else { return }

        let chat = ChatThread()
        chats.append(chat)
        selectedChatID = chat.id
    }

    private func selectInitialChat() {
        if let savedIDString = UserDefaults.standard.string(forKey: selectedChatIDKey),
           let savedID = UUID(uuidString: savedIDString),
           chats.contains(where: { $0.id == savedID }) {
            selectedChatID = savedID
        } else {
            selectedChatID = chats.first?.id
        }
    }

    private func saveChats() {
        guard historyAccessState == .unlocked, let historyEncryptionKey else { return }

        do {
            try chatStore.saveEncrypted(chats, key: historyEncryptionKey)
        } catch {
            assertionFailure("Could not save encrypted chats: \(error.localizedDescription)")
        }
    }

    private static func title(from prompt: String) -> String {
        let firstLine = prompt
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "New Chat"
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 42 else { return trimmed.isEmpty ? "New Chat" : trimmed }
        return String(trimmed.prefix(39)) + "..."
    }

    private static func translationSystemPrompt(targetLanguage: String) -> String {
        """
        You are a translation engine. Translate the user's word, phrase, or sentences into \(targetLanguage). Return only the translated text. Do not answer questions, explain, summarize, transliterate unless needed, add quotation marks, add notes, add markdown, or include alternatives. Preserve line breaks, punctuation, names, numbers, and formatting as closely as possible.
        """
    }
}
