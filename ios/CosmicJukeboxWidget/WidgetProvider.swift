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

    private func makeEntry() async -> JukeboxEntry {
        let snap = JukeboxShared.snapshot()
        var data: Data? = nil
        if let id = snap.trackId {
            if let cached = JukeboxShared.cachedArtwork(trackId: id) {
                data = cached
            } else if let urlStr = snap.artworkURL, let url = URL(string: urlStr) {
                if let (bytes, _) = try? await URLSession.shared.data(from: url) {
                    data = bytes
                    JukeboxShared.cacheArtwork(bytes, trackId: id)
                }
            }
        }
        return JukeboxEntry(date: Date(), snapshot: snap, artworkData: data)
    }
}
