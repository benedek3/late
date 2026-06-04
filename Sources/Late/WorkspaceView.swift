import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.74)

            Group {
                if !appState.isConfigured {
                    SetupView()
                } else if appState.historyAccessState != .unlocked {
                    HistoryAccessView()
                } else {
                    ChatView()
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 820, minHeight: 620)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SetupView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Late")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("A dark, blurred AI workspace that opens wherever you are.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("OpenRouter API Key")
                    .font(.headline)
                SecureField("sk-or-...", text: $appState.setupAPIKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .padding(14)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .onSubmit(appState.saveAPIKey)
                Text("Your key is stored locally in macOS Keychain and is only used to call OpenRouter from this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: 12) {
                Label("Menu bar", systemImage: "menubar.rectangle")
                Label(appState.selectedShortcut.label, systemImage: "keyboard")
                Spacer()
                Button("Continue") {
                    appState.saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(appState.setupAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

private struct HistoryAccessView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isPasswordFocused: Bool
    @State private var password = ""
    @State private var confirmation = ""

    private var isSetup: Bool {
        appState.historyAccessState == .setup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isSetup ? "Protect history" : "Unlock history")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(isSetup ? "Create a local password to encrypt your saved chats." : "Enter your local history password to load saved chats.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("History Password")
                    .font(.headline)
                SecureField("Password", text: $password)
                    .focused($isPasswordFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding(14)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .onSubmit(submit)

                if isSetup {
                    SecureField("Confirm password", text: $confirmation)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(14)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .onSubmit(submit)
                }

                Text("Your password is not stored. Chat history is encrypted locally before it is written to disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: 12) {
                Label("Encrypted history", systemImage: "lock.shield")
                Spacer()
                Button(isSetup ? "Create Password" : "Unlock") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isSubmitDisabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .onAppear {
            isPasswordFocused = true
        }
    }

    private var isSubmitDisabled: Bool {
        if isSetup {
            return password.isEmpty || confirmation.isEmpty
        }

        return password.isEmpty
    }

    private func submit() {
        if isSetup {
            appState.createHistoryPassword(password: password, confirmation: confirmation)
        } else {
            appState.unlockHistory(password: password)
        }

        if appState.historyAccessState == .unlocked {
            password = ""
            confirmation = ""
        }
    }
}

private struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isPromptFocused: Bool
    @State private var isHistoryRevealHovered = false
    @State private var isSettingsPresented = false
    @State private var sendTask: Task<Void, Never>?
    @State private var translationAutoTask: Task<Void, Never>?
    @State private var isAutoTranslateEnabled = true
    @State private var lastAutoTranslationKey = ""
    @State private var pendingAttachments: [ChatAttachment] = []

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if appState.isHistoryVisible && !appState.isTranslationMode {
                    chatList
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    header

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    if appState.isTranslationMode {
                        translator
                    } else {
                        transcript

                        composer
                    }
                }
            }

            if !appState.isHistoryVisible && !appState.isTranslationMode {
                hiddenHistoryHandle
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            isPromptFocused = true
        }
        .onChange(of: appState.focusToken) { _ in
            isPromptFocused = true
        }
        .onChange(of: appState.translationInput) { _ in
            scheduleAutoTranslation()
        }
        .onChange(of: appState.translationTargetLanguage) { _ in
            lastAutoTranslationKey = ""
            scheduleAutoTranslation()
        }
        .onChange(of: appState.isTranslationMode) { isTranslationMode in
            if isTranslationMode {
                scheduleAutoTranslation()
            } else {
                translationAutoTask?.cancel()
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsPanel()
                .environmentObject(appState)
        }
    }

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chats")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        appState.setHistoryVisible(false)
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.sortedChats) { chat in
                        HStack(spacing: 4) {
                            Button {
                                appState.selectChat(chat)
                                isPromptFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chat.title)
                                        .font(.callout.weight(chat.id == appState.selectedChatID ? .semibold : .regular))
                                        .lineLimit(2)
                                    Text(compactRelativeTime(from: chat.updatedAt))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .background(
                                    chat.id == appState.selectedChatID ? Color.white.opacity(0.10) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                appState.deleteChat(chat)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.sortedChats.count == 1)
                            .opacity(appState.sortedChats.count == 1 ? 0.25 : 0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 210)
        .background(Color.black.opacity(0.16))
    }

    private var hiddenHistoryHandle: some View {
        HStack(spacing: 0) {
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Text("History")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .opacity(isHistoryRevealHovered ? 1 : 0)
                .offset(x: isHistoryRevealHovered ? 12 : -26)
                Spacer()
            }
            .frame(width: 18)

            Spacer()
        }
        .frame(width: 18)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHistoryRevealHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                appState.setHistoryVisible(true)
                isHistoryRevealHovered = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.isTranslationMode ? "Translator" : appState.currentChat?.title ?? "New Chat")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.toggleTranslationMode()
                pendingAttachments.removeAll()
            } label: {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appState.isTranslationMode ? .black : .white)
                    .frame(width: 30, height: 30)
                    .background(appState.isTranslationMode ? Color.white : Color.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .help(appState.isTranslationMode ? "Back to chat" : "Translate")
            .buttonStyle(.plain)
            .keyboardShortcut("u", modifiers: .command)
            .disabled(appState.isLoading)

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func compactRelativeTime(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        let minutes = max(1, seconds / 60)

        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = max(1, minutes / 60)
        if hours < 24 {
            return "\(hours) hr ago"
        }

        let days = max(1, hours / 24)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    private var transcript: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 26) {
                if appState.currentMessages.isEmpty {
                    EmptyTranscriptView()
                        .frame(maxWidth: .infinity, minHeight: 330)
                } else {
                    ForEach(appState.currentMessages) { message in
                        MessageRow(
                            message: message,
                            showsActions: message.role == .assistant && !appState.isLoading && !message.content.isEmpty,
                            onRetry: {
                                startStreaming {
                                    await appState.retryResponse(id: message.id)
                                }
                            }
                        )
                            .id(message.id)
                    }
                }

                if appState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.vertical, 8)
                }

                Color.clear
                    .frame(height: 96)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
        }
    }

    private var translator: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                translationPanel(title: "Source") {
                    ZStack(alignment: .topLeading) {
                        if appState.translationInput.isEmpty {
                            Text("Text to translate")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        }

                        ScrollbarFreeTextView(text: $appState.translationInput)
                            .focused($isPromptFocused)
                    }
                }

                translationPanel(title: "Translation") {
                    ScrollView(.vertical, showsIndicators: false) {
                        if appState.translationOutput.isEmpty {
                            Text(appState.isLoading ? "" : "Translated text")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            Text(appState.translationOutput)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(AppState.translationLanguages, id: \.self) { language in
                        Button {
                            appState.translationTargetLanguage = language
                        } label: {
                            if appState.translationTargetLanguage == language {
                                Label(language, systemImage: "checkmark")
                            } else {
                                Text(language)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(appState.translationTargetLanguage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(appState.isLoading)

                Button {
                    isAutoTranslateEnabled.toggle()
                    if isAutoTranslateEnabled {
                        scheduleAutoTranslation()
                    } else {
                        translationAutoTask?.cancel()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Auto")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isAutoTranslateEnabled ? .black : .secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(isAutoTranslateEnabled ? Color.white : Color.white.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .help("Auto translate after typing")
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.translationOutput, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .help("Copy translation")
                .buttonStyle(.plain)
                .disabled(appState.translationOutput.isEmpty)
                .opacity(appState.translationOutput.isEmpty ? 0.35 : 1)

                if appState.isLoading || !isAutoTranslateEnabled {
                    Button {
                        if appState.isLoading {
                            sendTask?.cancel()
                        } else {
                            startTranslation()
                        }
                    } label: {
                        Image(systemName: appState.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(Color.white, in: Circle())
                            .contentShape(Circle())
                    }
                    .help(appState.isLoading ? "Stop" : "Translate")
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!appState.isLoading && appState.translationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(!appState.isLoading && appState.translationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(24)
    }

    private func translationPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Ask anything...", text: $appState.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .lineLimit(1...4)
                    .focused($isPromptFocused)
                    .padding(.horizontal, 2)
                    .padding(.top, 6)

                if !pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingAttachments) { attachment in
                                AttachmentThumbnail(attachment: attachment) {
                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                    }
                    .frame(height: 58)
                }

                HStack(alignment: .center, spacing: 12) {
                    Menu {
                        Button {
                            addFileAttachments()
                        } label: {
                            Label("Upload file", systemImage: "paperclip")
                        }

                        Button {
                            addImageAttachments()
                        } label: {
                            Label("Upload image", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .help("Add upload")
                    .buttonStyle(.plain)
                    .disabled(appState.isLoading)
                    .opacity(appState.isLoading ? 0.35 : 1)

                    Button {
                        appState.isWebSearchEnabled.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Web")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(appState.isWebSearchEnabled ? .black : .secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(appState.isWebSearchEnabled ? Color.white : Color.white.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 12)

                    Menu {
                        ForEach(AppState.availableModels) { model in
                            Button {
                                appState.selectedModel = model.id
                            } label: {
                                if appState.selectedModel == model.id {
                                    Label(model.name, systemImage: "checkmark")
                                } else {
                                    Text(model.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(compactModelName(appState.selectedModelName))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if appState.isLoading {
                            sendTask?.cancel()
                        } else {
                            let attachments = pendingAttachments
                            pendingAttachments = []
                            startStreaming {
                                await appState.sendPrompt(attachments: attachments)
                            }
                        }
                    } label: {
                        Image(systemName: appState.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(Color.white, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!appState.isLoading && appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                    .opacity(!appState.isLoading && appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty ? 0.35 : 1)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 9)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func compactModelName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "GPT-", with: "")
            .replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: "OpenRouter Auto", with: "Auto")
    }

    private func addImageAttachments() {
        addAttachments(allowedContentTypes: [.image])
    }

    private func addFileAttachments() {
        addAttachments(allowedContentTypes: nil)
    }

    private func addAttachments(allowedContentTypes: [UTType]?) {
        let panel = NSOpenPanel()
        if let allowedContentTypes {
            panel.allowedContentTypes = allowedContentTypes
        }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        let attachments = panel.urls.compactMap { url -> ChatAttachment? in
            guard let data = try? Data(contentsOf: url),
                  let attachmentMetadata = metadata(for: url) else {
                return nil
            }

            let dataURL = "data:\(attachmentMetadata.mimeType);base64,\(data.base64EncodedString())"
            return ChatAttachment(kind: attachmentMetadata.kind, name: url.lastPathComponent, mimeType: attachmentMetadata.mimeType, dataURL: dataURL)
        }

        pendingAttachments.append(contentsOf: attachments)
    }

    private func metadata(for url: URL) -> (kind: ChatAttachment.Kind, mimeType: String)? {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return (.file, "application/octet-stream")
        }

        let kind: ChatAttachment.Kind = type.conforms(to: .image) ? .image : .file
        return (kind, type.preferredMIMEType ?? "application/octet-stream")
    }

    private func scheduleAutoTranslation() {
        translationAutoTask?.cancel()
        guard appState.isTranslationMode, isAutoTranslateEnabled else { return }

        let source = appState.translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            lastAutoTranslationKey = ""
            return
        }

        let translationKey = "\(appState.translationTargetLanguage)\n\(source)"
        guard translationKey != lastAutoTranslationKey else { return }

        translationAutoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }

            let currentSource = appState.translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentKey = "\(appState.translationTargetLanguage)\n\(currentSource)"
            guard !currentSource.isEmpty, currentKey == translationKey, currentKey != lastAutoTranslationKey else { return }

            lastAutoTranslationKey = currentKey
            if appState.isLoading {
                sendTask?.cancel()
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
            }

            startTranslation()
        }
    }

    private func startTranslation() {
        translationAutoTask?.cancel()
        startStreaming {
            await appState.translateText()
        }
    }

    private func startStreaming(_ operation: @escaping @MainActor () async -> Void) {
        sendTask?.cancel()
        sendTask = Task {
            await operation()
            await MainActor.run {
                sendTask = nil
            }
        }
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("OpenRouter key and appearance shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenRouter API Key")
                    .font(.headline)
                SecureField("Paste a new key to replace the current one", text: $appState.settingsAPIKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )

                HStack {
                    Text("Leave blank to keep the saved key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save Key") {
                        appState.saveSettingsAPIKey()
                    }
                    .disabled(appState.settingsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Command To Appear")
                    .font(.headline)

                Picker("Command To Appear", selection: $appState.selectedShortcut) {
                    ForEach(AppearanceShortcut.allCases) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 360)
        .background(Color.black.opacity(0.96))
        .environment(\.colorScheme, .dark)
    }
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Start a workspace thread")
                .font(.title3.weight(.semibold))
            Text("Ask a question below. Use New to start another chat without deleting this one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

private struct ScrollbarFreeTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }

        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let showsActions: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .user ? "You" : "Late")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)

            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment)
                        }
                    }
                }
                .frame(height: 70)
            }

            FormattedMessageText(message.content)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !message.sources.isEmpty {
                SourceList(sources: message.sources)
            }

            if showsActions {
                HStack(spacing: 8) {
                    if let modelName = message.modelName {
                        Text(modelName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy")
                    .buttonStyle(MessageActionButtonStyle())

                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Try again")
                    .buttonStyle(MessageActionButtonStyle())
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttachmentThumbnail: View {
    let attachment: ChatAttachment
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = attachment.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: attachment.fileIconName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(1)
                            Text(attachment.fileExtensionLabel)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: attachment.kind == .image ? 64 : 132, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.black.opacity(0.64), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Remove attachment")
            }
        }
        .help(attachment.name)
    }
}

private extension ChatAttachment {
    var image: NSImage? {
        guard kind == .image else { return nil }
        guard let base64 = dataURL.components(separatedBy: "base64,").last,
              let data = Data(base64Encoded: base64) else {
            return nil
        }

        return NSImage(data: data)
    }

    var fileIconName: String {
        if mimeType == "application/pdf" {
            return "doc.richtext"
        }

        if mimeType.hasPrefix("text/") {
            return "doc.text"
        }

        return "doc"
    }

    var fileExtensionLabel: String {
        let pathExtension = (name as NSString).pathExtension
        guard !pathExtension.isEmpty else { return "FILE" }
        return pathExtension.uppercased()
    }
}

private struct MessageActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
            .contentShape(Capsule())
    }
}

private struct SourceList: View {
    let sources: [ChatSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(spacing: 7) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text(source.title?.isEmpty == false ? source.title! : source.url)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(source.title?.isEmpty == false ? source.title! : source.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct FormattedMessageText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        let blocks = MessageFormatter.blocks(from: content)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading:
                    Text(block.text)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding(.top, 4)
                case .paragraph:
                    MarkdownLine(block.text)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .lineSpacing(4)
                case .listItem(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, alignment: .trailing)

                        MarkdownLine(block.text)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .lineSpacing(4)
                    }
                case .code:
                    Text(block.text)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct MarkdownLine: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: content, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(content)
        }
    }
}

private struct MessageFormatter {
    struct Block {
        let kind: Kind
        let text: String
    }

    enum Kind {
        case heading
        case paragraph
        case listItem(String)
        case code
    }

    static func blocks(from content: String) -> [Block] {
        let readable = readableText(from: content)
        let lines = readable.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(Block(kind: .paragraph, text: text))
            }
            paragraph.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(Block(kind: .code, text: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                } else {
                    flushParagraph()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = headingText(from: line) {
                flushParagraph()
                blocks.append(Block(kind: .heading, text: heading))
                continue
            }

            if let listItem = listItem(from: line) {
                flushParagraph()
                blocks.append(listItem)
                continue
            }

            paragraph.append(line)
        }

        flushParagraph()

        if !codeLines.isEmpty {
            blocks.append(Block(kind: .code, text: codeLines.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [Block(kind: .paragraph, text: content)] : blocks
    }

    private static func readableText(from content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        text = replace(text, pattern: #"(?<=[\.:!?])\s*(\d+[\.)])\s*"#, template: "\n\n$1 ")
        text = replace(text, pattern: #"(?<=[\.!?])\s*([A-Z][A-Za-z /+\-]{2,32}:)"#, template: "\n\n$1")
        text = replace(text, pattern: #"([A-Za-z][A-Za-z /+\-]{2,32}:)(?=[A-Z])"#, template: "$1\n")
        text = replace(text, pattern: #"(?<=[a-z\)])\s+(Mon:|Tue:|Wed:|Thu:|Fri:|Sat:|Sun:)"#, template: "\n$1")
        text = replace(text, pattern: #"\n{3,}"#, template: "\n\n")
        return text
    }

    private static func headingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return heading.isEmpty ? nil : heading
    }

    private static func listItem(from line: String) -> Block? {
        let patterns = [
            (#"^(\d+[\.)])\s+(.+)$"#, true),
            (#"^([-*•])\s+(.+)$"#, false)
        ]

        for (pattern, keepsMarker) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let markerRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            let marker = keepsMarker ? String(line[markerRange]) : "•"
            return Block(kind: .listItem(marker), text: String(line[textRange]))
        }

        return nil
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
