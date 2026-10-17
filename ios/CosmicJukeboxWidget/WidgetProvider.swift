import WidgetKit
import SwiftUI

/// Timeline entry carrying the shared playback snapshot plus artwork bytes.
struct JukeboxEntry: TimelineEntry {
    let date: Date
    let snapshot: JukeboxShared.PlaybackSnapshot
    let artworkData: Data?
}

struct JukeboxProvider: TimelineProvider {
    func placeholder(in context: Context) -> JukeboxEntry {
        JukeboxEntry(
            date: Date(),
            snapshot: JukeboxShared.PlaybackSnapshot(
                trackId: nil, isPlaying: false,
                title: "Cosmic Jukebox", artist: "MikeGyver Studio",
                artworkURL: nil, heartbeat: nil
            ),
            artworkData: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (JukeboxEntry) -> Void) {
        Task {
            completion(await makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JukeboxEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // Re-check periodically; the app also pushes reloads on every change.
            let refresh = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    /// Builds the entry from the shared snapshot. Artwork comes ONLY from the
    /// shared-container cache — never the network. Doing a download inside
    /// getTimeline made refreshes slow and droppable: a stalled fetch meant
    /// WidgetKit kept the previous entry, so the widget showed the old
    /// song's cover (and old play/pause state) after a track change. The app
    /// downloads every cover for CarPlay anyway and reloads the widget when
    /// new art lands, so the cache is always warm a moment after a change.
    private func makeEntry() async -> JukeboxEntry {
        let snap = JukeboxShared.snapshot()
        let data: Data? = snap.trackId.flatMap { JukeboxShared.cachedArtwork(trackId: $0) }
        return JukeboxEntry(date: Date(), snapshot: snap, artworkData: data)
    }
}
