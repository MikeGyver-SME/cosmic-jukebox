import SwiftUI

@main
struct CosmicJukeboxApp: App {
    @StateObject private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear { engine.start() }
                .onOpenURL(perform: handleURL)
        }
    }

    /// Handles `cosmicjukebox://toggle` and `cosmicjukebox://play`
    /// (used by the widget's fallback Link when the app isn't alive).
    private func handleURL(_ url: URL) {
        guard url.scheme == "cosmicjukebox" else { return }
        switch url.host?.lowercased() {
        case "toggle":
            engine.toggle()
        case "play":
            engine.ensurePlaying()
        default:
            break
        }
    }
}
