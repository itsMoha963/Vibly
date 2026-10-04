import SwiftUI

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}

struct ConnectionBadge: View {
    let state: DiscordConnectionState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.isReady ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(state.title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: PresenceViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            Color.primary.opacity(0.025)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), .clear, Color.indigo.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.thinMaterial)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.85), Color.indigo.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(0.85)
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vibly")
                            .font(.title.weight(.bold))
                        Text("Your Discord presence, your way.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    ConnectionBadge(state: model.connectionState)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)

                TabView(selection: $selectedTab) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ManualPresenceView()
                        }
                        .padding(24)
                    }
                    .tabItem {
                        Label("New", systemImage: "plus")
                    }
                    .tag(0)

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(1)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 650)
        .task {
            model.start()
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var model: PresenceViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Vibly") {
            openWindow(id: "main")
        }

        Divider()

        if let currentPresence = model.currentPresence {
            Text(currentPresence.activity)
            Button("Clear Presence") {
                model.clearPresence()
            }
        } else {
            Text("No active presence")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Quit Vibly") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
