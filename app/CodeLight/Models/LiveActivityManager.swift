import ActivityKit
import Foundation
import os.log

/// Manages Live Activities for active Claude Code sessions.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private static let logger = Logger(subsystem: "com.codelight.app", category: "LiveActivity")

    /// Active Live Activities keyed by sessionId.
    private var activities: [String: Activity<CodeLightActivityAttributes>] = [:]

    private init() {}

    /// Start or update a Live Activity for a session.
    func update(sessionId: String, phase: String, toolName: String?, projectName: String, serverName: String) {
        if let existing = activities[sessionId] {
            // Update existing activity
            let state = CodeLightActivityAttributes.ContentState(
                phase: phase,
                toolName: toolName,
                projectName: projectName,
                startedAt: Date()
            )
            Task {
                await existing.update(ActivityContent(state: state, staleDate: nil))
                Self.logger.debug("Updated activity for \(sessionId): \(phase)")
            }
        } else {
            // Start new activity
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                Self.logger.info("Live Activities not enabled")
                return
            }

            let attributes = CodeLightActivityAttributes(sessionId: sessionId, serverName: serverName)
            let state = CodeLightActivityAttributes.ContentState(
                phase: phase,
                toolName: toolName,
                projectName: projectName,
                startedAt: Date()
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                activities[sessionId] = activity
                Self.logger.info("Started activity for \(sessionId)")
            } catch {
                Self.logger.error("Failed to start activity: \(error)")
            }
        }
    }

    /// End the Live Activity for a session.
    func end(sessionId: String) {
        guard let activity = activities.removeValue(forKey: sessionId) else { return }

        let finalState = CodeLightActivityAttributes.ContentState(
            phase: "ended",
            toolName: nil,
            projectName: activity.content.state.projectName,
            startedAt: Date()
        )

        Task {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 5))
            Self.logger.info("Ended activity for \(sessionId)")
        }
    }

    /// End all active Live Activities.
    func endAll() {
        for (sessionId, _) in activities {
            end(sessionId: sessionId)
        }
    }
}
