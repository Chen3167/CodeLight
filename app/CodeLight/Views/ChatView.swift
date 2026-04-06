import SwiftUI
import PhotosUI

/// A pending image attachment in the compose bar (before send).
struct PendingAttachment: Identifiable {
    let id = UUID()
    let data: Data      // compressed JPEG, ready to upload
    let thumbnail: UIImage
}

/// A conversation turn — user question + all Claude's responses until next user message.
struct ConversationTurn: Identifiable {
    let id: String          // Uses user message ID (or "initial" if no user msg)
    let userMessage: ChatMessage?
    let replies: [ChatMessage]
    let firstSeq: Int       // For sorting
    let questionText: String // For navigation

    var anchorId: String { id }
}

/// Chat view with markdown rendering, lazy loading, and turn-based grouping.
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var pickerSelections: [PhotosPickerItem] = []
    @State private var isSending = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMoreOlder = false
    @State private var selectedModel = "opus"
    @State private var selectedMode = "auto"
    @State private var showQuestionNav = false
    @State private var expandedTurns = Set<String>()
    @State private var shouldAutoScroll = true
    @State private var lastSeenSeq: Int = 0

    private let models = ["opus", "sonnet", "haiku"]
    private let modes = ["auto", "default", "plan"]

    // Group messages into turns
    private var turns: [ConversationTurn] {
        groupMessagesIntoTurns(messages)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages grouped into turns with lazy loading
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Load more button at top
                        if hasMoreOlder {
                            Button {
                                Task { await loadOlderMessages() }
                            } label: {
                                if isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                } else {
                                    Text(String(localized: "load_earlier_messages"))
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                }
                            }
                            .id("loadMore")
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }

                        ForEach(turns) { turn in
                            TurnView(turn: turn, isExpanded: isExpanded(turn), onToggle: { toggleTurn(turn) })
                                .id(turn.anchorId)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.last?.seq ?? 0) { oldSeq, newSeq in
                    // Only scroll to bottom when NEW messages arrive (seq increases),
                    // not when older messages are prepended.
                    guard shouldAutoScroll && newSeq > oldSeq else { return }
                    if let lastTurn = turns.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastTurn.anchorId, anchor: .bottom)
                        }
                    }
                }
                .sheet(isPresented: $showQuestionNav) {
                    QuestionNavSheet(turns: turns) { turnId in
                        showQuestionNav = false
                        expandedTurns.insert(turnId)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(turnId, anchor: .top)
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }

            Divider()

            // Input bar
            composeBar
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showQuestionNav = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
            }
        }
        .task {
            await loadMessages()
            startLiveActivity()
        }
        .onReceive(appState.newMessageSubject) { event in
            guard event.sessionId == sessionId else { return }
            // Replace optimistic local message if server echoes back with same localId.
            if let lid = event.message.localId,
               let idx = messages.firstIndex(where: { $0.localId == lid }) {
                messages[idx] = event.message
                return
            }
            // Otherwise dedup by id and append.
            if !messages.contains(where: { $0.id == event.message.id }) {
                messages.append(event.message)
            }
        }
    }

    // MARK: - Turn State

    private func isExpanded(_ turn: ConversationTurn) -> Bool {
        // The last turn is always expanded by default; others follow user toggle
        if turn.id == turns.last?.id { return true }
        return expandedTurns.contains(turn.id)
    }

    private func toggleTurn(_ turn: ConversationTurn) {
        if expandedTurns.contains(turn.id) {
            expandedTurns.remove(turn.id)
        } else {
            expandedTurns.insert(turn.id)
        }
    }

    // MARK: - Turn Grouping

    private func groupMessagesIntoTurns(_ messages: [ChatMessage]) -> [ConversationTurn] {
        var turns: [ConversationTurn] = []
        var currentUserMsg: ChatMessage?
        var currentReplies: [ChatMessage] = []
        var currentFirstSeq: Int = 0
        var initialReplies: [ChatMessage] = []

        func flushCurrent() {
            if let user = currentUserMsg {
                let question = extractTextFromMessage(user)
                turns.append(ConversationTurn(
                    id: user.id,
                    userMessage: user,
                    replies: currentReplies,
                    firstSeq: currentFirstSeq,
                    questionText: question
                ))
            }
            currentUserMsg = nil
            currentReplies = []
        }

        for msg in messages {
            let type = messageType(msg)

            if type == "user" {
                flushCurrent()
                currentUserMsg = msg
                currentFirstSeq = msg.seq
            } else if currentUserMsg != nil {
                currentReplies.append(msg)
            } else {
                initialReplies.append(msg)
            }
        }
        flushCurrent()

        // Prepend initial replies (before first user message) if any
        if !initialReplies.isEmpty {
            turns.insert(ConversationTurn(
                id: "initial-\(initialReplies.first?.id ?? "")",
                userMessage: nil,
                replies: initialReplies,
                firstSeq: initialReplies.first?.seq ?? 0,
                questionText: String(localized: "session_start")
            ), at: 0)
        }

        return turns
    }

    private func messageType(_ msg: ChatMessage) -> String {
        if let data = msg.content.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = dict["type"] as? String {
            return type
        }
        return "user" // Plain text = user message from phone
    }

    private func extractTextFromMessage(_ msg: ChatMessage) -> String {
        if let data = msg.content.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = dict["text"] as? String {
            return text
        }
        return msg.content
    }

    private func startLiveActivity() {
        // Delay to ensure app is fully visible (fixes "visibility" error on launch)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await MainActor.run { doStartLiveActivity() }
        }
    }

    private func doStartLiveActivity() {
        // Delegate to AppState's global activity manager
        appState.startLiveActivitiesForActiveSessions()
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(models, id: \.self) { model in
                        Button(model.capitalized) {
                            selectedModel = model
                            appState.updateModelMode(sessionId: sessionId, model: model, mode: selectedMode)
                        }
                    }
                } label: {
                    Label(selectedModel.capitalized, systemImage: "cpu")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Menu {
                    ForEach(modes, id: \.self) { mode in
                        Button(mode.capitalized) {
                            selectedMode = mode
                            appState.updateModelMode(sessionId: sessionId, model: selectedModel, mode: mode)
                        }
                    }
                } label: {
                    Label(selectedMode.capitalized, systemImage: "shield")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()
            }

            // Attachment thumbnails
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { att in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: att.thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    pendingAttachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, .black.opacity(0.7))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 72)
            }

            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $pickerSelections,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .onChange(of: pickerSelections) { _, newItems in
                    Task { await loadPickedImages(newItems) }
                }

                TextField(String(localized: "message_placeholder"), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .lineLimit(1...5)

                Button { send() } label: {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .blue : .gray)
                    }
                }
                .disabled(!canSend || isSending)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    /// Read selected PhotosPicker items, compress, and stage them as attachments.
    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        var newAttachments: [PendingAttachment] = []
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let compressed = ImageCompressor.compress(raw) else { continue }
            guard let thumb = UIImage(data: compressed) else { continue }
            newAttachments.append(PendingAttachment(data: compressed, thumbnail: thumb))
        }
        await MainActor.run {
            pendingAttachments.append(contentsOf: newAttachments)
            pickerSelections.removeAll()
        }
    }

    // MARK: - Data

    private var sessionTitle: String {
        appState.sessions.first { $0.id == sessionId }?.metadata?.displayProjectName ?? String(localized: "session")
    }

    private func loadMessages() async {
        // Initial load only — never destructively replace once we have data.
        // New messages stream in via newMessageSubject; older ones come from the
        // explicit "Load earlier" button. This guard makes the function safe even
        // if SwiftUI re-runs the .task closure for any reason.
        guard messages.isEmpty else { return }
        isLoading = true
        if let socket = appState.socket {
            let result = (try? await socket.fetchMessages(sessionId: sessionId, limit: 50)) ?? SocketClient.FetchResult(messages: [], hasMore: false)
            messages = result.messages
            hasMoreOlder = result.hasMore
        }
        isLoading = false
    }

    private func loadOlderMessages() async {
        guard !isLoadingMore, let oldest = messages.first else { return }
        isLoadingMore = true
        if let socket = appState.socket {
            let result = (try? await socket.fetchOlderMessages(sessionId: sessionId, beforeSeq: oldest.seq, limit: 50)) ?? SocketClient.FetchResult(messages: [], hasMore: false)
            messages.insert(contentsOf: result.messages, at: 0)
            hasMoreOlder = result.hasMore
        }
        isLoadingMore = false
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsToSend = pendingAttachments
        guard !text.isEmpty || !attachmentsToSend.isEmpty else { return }

        inputText = ""
        pendingAttachments = []
        isSending = true

        Task {
            // Upload blobs first (if any), keeping the raw data in a local cache so
            // MessageRow can render the image immediately in history.
            var blobIds: [String] = []
            if !attachmentsToSend.isEmpty, let socket = appState.socket {
                for att in attachmentsToSend {
                    if let id = try? await socket.uploadBlob(data: att.data, mime: "image/jpeg") {
                        blobIds.append(id)
                        await MainActor.run { appState.sentImageCache[id] = att.data }
                    }
                }
            }

            // Compose payload. If there are blobs, send JSON; otherwise keep plain text so
            // CodeIsland's existing "plain text = user message" path still works.
            let payloadString: String
            if !blobIds.isEmpty {
                var payload: [String: Any] = ["type": "user", "text": text]
                payload["images"] = blobIds.map { ["blobId": $0, "mime": "image/jpeg"] }
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let str = String(data: data, encoding: .utf8) {
                    payloadString = str
                } else {
                    payloadString = text
                }
            } else {
                payloadString = text
            }

            // Share one localId between the socket emit and the optimistic
            // ChatMessage so the server echo can replace the local row instead
            // of producing a duplicate.
            let localId = UUID().uuidString
            await MainActor.run {
                appState.sendMessage(payloadString, toSession: sessionId, localId: localId)
                let msg = ChatMessage(id: "local-\(localId)",
                                      seq: (messages.last?.seq ?? 0) + 1,
                                      content: payloadString,
                                      localId: localId)
                messages.append(msg)
                isSending = false
            }
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage

    var body: some View {
        let parsed = parseContent(message.content)

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: roleIcon(parsed.type))
                .font(.system(size: 10))
                .foregroundStyle(roleColor(parsed.type))
                .frame(width: 14, height: 14)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(roleLabel(parsed.type))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(roleColor(parsed.type))
                    .textCase(.uppercase)

                switch parsed.type {
                case "tool":
                    toolView(parsed)
                case "thinking":
                    thinkingView(parsed)
                case "interrupted":
                    Label(String(localized: "interrupted_by_user"), systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    if !parsed.text.isEmpty {
                        markdownContent(parsed.text)
                    }
                    if !parsed.imageBlobIds.isEmpty {
                        attachmentsView(blobIds: parsed.imageBlobIds)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func attachmentsView(blobIds: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(blobIds, id: \.self) { id in
                    if let data = appState.sentImageCache[id],
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Markdown Rendering

    @ViewBuilder
    private func markdownContent(_ text: String) -> some View {
        let parts = splitCodeBlocks(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isCode {
                    codeBlockView(part)
                } else if !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Use AttributedString for inline markdown
                    if let attributed = try? AttributedString(markdown: part.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    } else {
                        Text(part.text)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func codeBlockView(_ part: TextPart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !part.language.isEmpty {
                HStack {
                    Text(part.language)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = part.text
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(part.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tool / Thinking Views

    private func toolView(_ parsed: ParsedMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(parsed.toolName ?? ""))
                    .font(.system(size: 10))
                Text(parsed.toolName ?? "tool")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let status = parsed.toolStatus {
                    Text(status)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.2), in: Capsule())
                        .foregroundStyle(statusColor(status))
                }
            }

            if !parsed.text.isEmpty {
                Text(parsed.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func thinkingView(_ parsed: ParsedMessage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 10))
            Text(parsed.text.isEmpty ? String(localized: "thinking_ellipsis") : parsed.text)
                .font(.caption)
                .italic()
                .lineLimit(3)
        }
        .foregroundStyle(.purple.opacity(0.8))
        .padding(6)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Code Block Parsing

    private struct TextPart {
        let text: String
        let isCode: Bool
        let language: String
    }

    private func splitCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [TextPart(text: text, isCode: false, language: "")]
        }

        let nsText = text as NSString
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if beforeRange.length > 0 {
                parts.append(TextPart(text: nsText.substring(with: beforeRange), isCode: false, language: ""))
            }
            let lang = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            parts.append(TextPart(text: code, isCode: true, language: lang))
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            parts.append(TextPart(text: nsText.substring(from: lastEnd), isCode: false, language: ""))
        }

        return parts.isEmpty ? [TextPart(text: text, isCode: false, language: "")] : parts
    }

    // MARK: - Parse

    private struct ParsedMessage {
        let type: String
        let text: String
        let toolName: String?
        let toolStatus: String?
        let imageBlobIds: [String]
    }

    private func parseContent(_ content: String) -> ParsedMessage {
        if let data = content.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = dict["type"] as? String {
            var blobIds: [String] = []
            if let images = dict["images"] as? [[String: Any]] {
                blobIds = images.compactMap { $0["blobId"] as? String }
            }
            return ParsedMessage(
                type: type,
                text: dict["text"] as? String ?? "",
                toolName: dict["toolName"] as? String,
                toolStatus: dict["toolStatus"] as? String,
                imageBlobIds: blobIds
            )
        }
        return ParsedMessage(type: "user", text: content, toolName: nil, toolStatus: nil, imageBlobIds: [])
    }

    // MARK: - Style Helpers

    private func roleColor(_ type: String) -> Color {
        switch type {
        case "user": return .blue
        case "assistant": return .green
        case "thinking": return .purple
        case "tool": return .cyan
        case "interrupted": return .red
        default: return .gray
        }
    }

    private func roleIcon(_ type: String) -> String {
        switch type {
        case "user": return "person.fill"
        case "assistant": return "sparkles"
        case "thinking": return "brain"
        case "tool": return "wrench.and.screwdriver.fill"
        case "interrupted": return "stop.circle.fill"
        default: return "circle"
        }
    }

    private func roleLabel(_ type: String) -> String {
        switch type {
        case "user": return String(localized: "role_you")
        case "assistant": return String(localized: "role_claude")
        case "thinking": return String(localized: "role_thinking")
        case "tool": return String(localized: "role_tool")
        case "interrupted": return String(localized: "role_interrupted")
        default: return type
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "doc.badge.plus"
        case "edit": return "pencil"
        case "glob": return "folder.badge.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "agent": return "person.2"
        case "task": return "checklist"
        default: return "gearshape"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success", "completed": return .green
        case "error", "failed": return .red
        case "running", "pending": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Turn View

private struct TurnView: View {
    let turn: ConversationTurn
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // User question header
            if turn.userMessage != nil {
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                            .frame(width: 16, height: 16)
                            .background(.blue.opacity(0.15), in: Circle())

                        Text(turn.questionText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                // Initial replies (no user message)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(turn.questionText)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }

            // Replies (collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.replies) { reply in
                        MessageRow(message: reply)
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !turn.replies.isEmpty {
                // Collapsed summary
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.bubble")
                        .font(.caption2)
                    Text("\(turn.replies.count) \(String(localized: "replies"))")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Question Navigation Sheet

private struct QuestionNavSheet: View {
    let turns: [ConversationTurn]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if turns.isEmpty {
                    ContentUnavailableView(
                        String(localized: "no_questions_yet"),
                        systemImage: "questionmark.bubble"
                    )
                } else {
                    ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                        Button {
                            onSelect(turn.anchorId)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.blue, in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(turn.questionText)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)

                                    if turn.replies.count > 0 {
                                        Text("\(turn.replies.count) \(String(localized: "replies"))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "arrow.up.forward")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(String(localized: "jump_to_question"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
        }
    }
}
