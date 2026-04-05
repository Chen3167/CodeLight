import SwiftUI

/// List of sessions for a given server.
struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    let server: ServerConfig
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions...")
            } else if appState.sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a Claude Code session on your Mac")
                )
            } else {
                List {
                    // Active sessions
                    let active = appState.sessions.filter(\.active)
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active) { session in
                                NavigationLink(value: session.id) {
                                    SessionRow(session: session)
                                }
                            }
                        }
                    }

                    // Inactive sessions
                    let inactive = appState.sessions.filter { !$0.active }
                    if !inactive.isEmpty {
                        Section("Recent") {
                            ForEach(inactive) { session in
                                NavigationLink(value: session.id) {
                                    SessionRow(session: session)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationDestination(for: String.self) { sessionId in
            ChatView(sessionId: sessionId)
        }
        .task {
            // Don't re-connect, RootView already did that
            if let socket = appState.socket {
                do {
                    appState.sessions = try await socket.fetchSessions()
                    print("[SessionList] Loaded \(appState.sessions.count) sessions")
                } catch {
                    print("[SessionList] Fetch error: \(error)")
                }
            } else {
                print("[SessionList] No socket available")
            }
            isLoading = false
        }
    }
}

/// A single session row.
private struct SessionRow: View {
    let session: SessionInfo

    var body: some View {
        HStack {
            Circle()
                .fill(session.active ? .green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.metadata?.title ?? session.tag)
                    .font(.headline)
                    .lineLimit(1)

                if let path = session.metadata?.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(session.lastActiveAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
