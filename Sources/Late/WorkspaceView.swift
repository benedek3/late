import AppKit
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.74)

            Group {
                if appState.isConfigured {
                    ChatView()
                } else {
                    SetupView()
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

private struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isPromptFocused: Bool
    @State private var isHistoryRevealHovered = false
    @State private var isSettingsPresented = false
    @State private var sendTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if appState.isHistoryVisible {
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

                    transcript

                    composer
                }
            }

            if !appState.isHistoryVisible {
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
                Text(appState.currentChat?.title ?? "New Chat")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

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

                HStack(alignment: .center, spacing: 12) {
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
                            startStreaming {
                                await appState.sendPrompt()
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
                    .disabled(!appState.isLoading && appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(!appState.isLoading && appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
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

private struct MessageRow: View {
    let message: ChatMessage
    let showsActions: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .user ? "You" : "Late")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)

            FormattedMessageText(message.content)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !message.sources.isEmpty {
                SourceList(sources: message.sources)
            }

            if showsActions {
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(MessageActionButtonStyle())

                    Button(action: onRetry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MessageActionButtonStyle())
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .frame(height: 28)
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
