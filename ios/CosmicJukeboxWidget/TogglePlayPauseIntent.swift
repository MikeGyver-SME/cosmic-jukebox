import AppIntents
import WidgetKit

/// Flips playback without opening the app. The app (alive in the background)
/// observes the Darwin toggle notification and applies it to AVPlayer.
struct TogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Cosmic Jukebox playback"
    static var description = IntentDescription(
        "Plays or pauses the Cosmic Jukebox without opening the app."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let snap = JukeboxShared.snapshot()
        let newValue = !snap.isPlaying
        JukeboxShared.write(
            trackId: snap.trackId,
            isPlaying: newValue,
            title: snap.title,
            artist: snap.artist,
            artworkURL: snap.artworkURL
        )
        JukeboxShared.postDarwin(JukeboxShared.toggleNotification)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
