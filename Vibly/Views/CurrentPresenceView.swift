import SwiftUI

struct CurrentPresenceView: View {
    let presence: PresenceConfiguration?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Current presence", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                    Spacer()
                    if presence != nil {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }

                if let presence {
                    Text(presence.activity)
                        .font(.title3.weight(.semibold))
                    if !presence.details.isEmpty {
                        Text(presence.details)
                            .foregroundStyle(.secondary)
                    }
                    if !presence.state.isEmpty {
                        Text(presence.state)
                            .foregroundStyle(.secondary)
                    }
                    if presence.showElapsedTime, let startedAt = presence.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Label(
                                "\(elapsedText(since: startedAt, now: context.date)) elapsed",
                                systemImage: "timer"
                            )
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No presence is active.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func elapsedText(since start: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
