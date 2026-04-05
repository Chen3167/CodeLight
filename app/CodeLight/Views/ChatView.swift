import SwiftUI

/// Chat view for a single session — shows messages and allows sending.
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let sessionId: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var selectedModel = "opus"
    @State private var selectedMode = "auto"

    private let models = ["opus", "sonnet", "haiku"]
    private let modes = ["auto", "default", "plan"]

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Model/Mode selector + Input
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(models, id: \.self) { model in
                            Button(model.capitalized) { selectedModel = model }
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
                            Button(mode.capitalized) { selectedMode = mode }
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

                HStack(spacing: 8) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .lineLimit(1...5)

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
    }

    private var sessionTitle: String {
        appState.sessions.first { $0.id == sessionId }?.metadata?.title ?? "Session"
    }

    private func loadMessages() async {
        isLoading = true
        if let socket = appState.socket {
            messages = (try? await socket.fetchMessages(sessionId: sessionId)) ?? []
        }
        isLoading = false
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.sendMessage(text, toSession: sessionId)

        // Optimistic: add to local list
        let msg = ChatMessage(id: UUID().uuidString, seq: (messages.last?.seq ?? 0) + 1, content: text, localId: nil)
        messages.append(msg)
    }
}

/// A single message bubble.
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .font(.body)
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
