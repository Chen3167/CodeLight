import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity widget for Dynamic Island and Lock Screen.
struct CodeLightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodeLightActivityAttributes.self) { context in
            // Lock Screen / StandBy presentation
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.projectName, systemImage: phaseIcon(context.state.phase))
                        .font(.caption)
                        .foregroundStyle(phaseColor(context.state.phase))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let toolName = context.state.toolName {
                        HStack {
                            Image(systemName: "wrench.fill")
                                .font(.caption2)
                            Text(toolName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text(phaseLabel(context.state.phase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                // Compact leading — icon
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(phaseColor(context.state.phase))
            } compactTrailing: {
                // Compact trailing — timer
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2)
                    .frame(width: 40)
            } minimal: {
                // Minimal — just the icon
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(phaseColor(context.state.phase))
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let state: CodeLightActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: phaseIcon(state.phase))
                .font(.title2)
                .foregroundStyle(phaseColor(state.phase))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.projectName)
                    .font(.headline)
                    .lineLimit(1)

                if let toolName = state.toolName {
                    Text(toolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(phaseLabel(state.phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(state.startedAt, style: .timer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Phase Helpers

private func phaseIcon(_ phase: String) -> String {
    switch phase {
    case "thinking": return "brain"
    case "tool_running": return "wrench.and.screwdriver.fill"
    case "waiting_approval": return "exclamationmark.shield.fill"
    case "idle": return "pause.circle"
    case "ended": return "checkmark.circle"
    default: return "circle"
    }
}

private func phaseColor(_ phase: String) -> Color {
    switch phase {
    case "thinking": return .purple
    case "tool_running": return .cyan
    case "waiting_approval": return .orange
    case "idle": return .gray
    case "ended": return .green
    default: return .gray
    }
}

private func phaseLabel(_ phase: String) -> String {
    switch phase {
    case "thinking": return "Thinking..."
    case "tool_running": return "Running tool"
    case "waiting_approval": return "Needs approval"
    case "idle": return "Idle"
    case "ended": return "Done"
    default: return phase
    }
}
