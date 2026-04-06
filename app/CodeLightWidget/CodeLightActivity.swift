import ActivityKit
import Foundation

/// ActivityAttributes for CodeLight Live Activities (Dynamic Island + Lock Screen).
/// Shared between the main app and the widget extension.
struct CodeLightActivityAttributes: ActivityAttributes {
    /// Dynamic state — updated as session progresses.
    struct ContentState: Codable, Hashable {
        var phase: String              // "thinking", "tool_running", "waiting_approval", "idle", "ended", "error"
        var toolName: String?          // Current tool name (e.g., "Edit main.swift")
        var projectName: String        // Project / session title
        var lastUserMessage: String?   // Latest user question (truncated)
        var lastAssistantSummary: String?  // Latest Claude response summary (truncated)
        var startedAt: Date            // When this phase started
    }

    /// Fixed for the lifetime of the activity.
    var sessionId: String
    var serverName: String
}
