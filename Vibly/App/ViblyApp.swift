import SwiftUI

@main
struct ViblyApp: App {
    @StateObject private var model = PresenceViewModel()

    var body: some Scene {
        WindowGroup("Vibly", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 500, height: 700)

        MenuBarExtra("Vibly", systemImage: "waveform.path.ecg") {
            MenuBarContent()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
