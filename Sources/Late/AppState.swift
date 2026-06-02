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

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    enum Role: String, Codable {
        case user
        case assistant
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
    @Published var isHistoryVisible = true
    @Published var isWebSearchEnabled = false
    @Published var settingsAPIKey = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let keychain = KeychainStore()
    private let apiClient = OpenRouterClient()
    private let chatStore = ChatStore()
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

        let loadedChats = chatStore.load()
        self.chats = loadedChats.isEmpty ? [ChatThread()] : loadedChats

        if let savedIDString = UserDefaults.standard.string(forKey: selectedChatIDKey),
           let savedID = UUID(uuidString: savedIDString),
           self.chats.contains(where: { $0.id == savedID }) {
            self.selectedChatID = savedID
        } else {
            self.selectedChatID = self.chats.first?.id
        }

        saveChats()
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

    func sendPrompt() async {
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty, !isLoading else { return }
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

        chats[index].messages.append(ChatMessage(role: .user, content: userPrompt))
        chats[index].updatedAt = Date()

        if chats[index].title == "New Chat" {
            chats[index].title = Self.title(from: userPrompt)
        }

        let requestChatID = chats[index].id
        let requestMessages = chats[index].messages
        saveChats()

        do {
            let reply = try await apiClient.fetchReply(
                apiKey: apiKey,
                model: selectedModel,
                webSearchEnabled: isWebSearchEnabled,
                messages: requestMessages
            )
            if let index = chats.firstIndex(where: { $0.id == requestChatID }) {
                chats[index].messages.append(ChatMessage(role: .assistant, content: reply))
                chats[index].updatedAt = Date()
                saveChats()
            }
        } catch {
            errorMessage = error.localizedDescription
            saveChats()
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

    private func saveChats() {
        chatStore.save(chats)
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
}
