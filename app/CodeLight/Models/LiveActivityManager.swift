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
        print("[LiveActivity] update called: session=\(sessionId.prefix(8)) phase=\(phase) tool=\(toolName ?? "nil")")

        if let existing = activities[sessionId] {
            // Update existing activity
            let state = CodeLightActivityAttributes.ContentState(
                phase: phase,
                toolName: toolName,
                projectName: projectName,
                startedAt: existing.content.state.startedAt  // Keep original start time
            )
            Task {
                await existing.update(ActivityContent(state: state, staleDate: nil))
                print("[LiveActivity] Updated activity for \(sessionId.prefix(8))")
            }
        } else {
            // Start new activity
            let authInfo = ActivityAuthorizationInfo()
            print("[LiveActivity] Activities enabled: \(authInfo.areActivitiesEnabled), frequent push enabled: \(authInfo.frequentPushesEnabled)")

            guard authInfo.areActivitiesEnabled else {
                print("[LiveActivity] BLOCKED: Live Activities not enabled in iOS Settings")
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
                print("[LiveActivity] STARTED activity for \(sessionId.prefix(8))")
            } catch {
                print("[LiveActivity] FAILED to start: \(error)")
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
