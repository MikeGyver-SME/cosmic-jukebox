import AppIntents
import WidgetKit

/// Asks the app to toggle playback without opening it. The app is the single
/// source of truth: it applies the toggle on the main thread (so rapid taps
/// serialize instead of racing), writes the authoritative state to the App
/// Group, and reloads the widget timeline itself.
///
/// This intent deliberately does NOT flip the shared `isPlaying` flag. An
/// optimistic write here was the play/pause-inversion bug: two quick taps
/// could read the same stale value and both write the same flip while the
/// app received two toggle notifications (ending where it started), and a
/// toggle lost to a suspended app left the written lie on screen. It also
/// stamped a heartbeat from the widget process, hiding a dead app from the
/// widget's "tap to open the app" fallback.
struct TogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Cosmic Jukebox playback"
    static var description = IntentDescription(
        "Plays or pauses the Cosmic Jukebox without opening the app."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        JukeboxShared.postDarwin(JukeboxShared.toggleNotification)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
