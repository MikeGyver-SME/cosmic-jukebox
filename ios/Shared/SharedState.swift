import Foundation

/// Shared playback state between the Cosmic Jukebox app and its widget,
/// backed by the App Group `group.studio.mikegyver.cosmicjukebox`.
/// This file is compiled into BOTH the app target and the widget extension.
enum JukeboxShared {
    static let appGroupID = "group.studio.mikegyver.cosmicjukebox"

    /// Posted by the app whenever playback state changes.
    static let stateNotification = "studio.mikegyver.jukebox.state"
    /// Posted by the widget's AppIntent; the app observes it and toggles AVPlayer.
    static let toggleNotification = "studio.mikegyver.jukebox.toggle"

    /// Heartbeat younger than this means the app is (probably) alive.
    /// The app stamps one every 60s and the widget never writes one, so a
    /// stale value honestly means the app is gone and the widget falls back
    /// to its "tap to open the app" link.
    static let heartbeatFreshInterval: TimeInterval = 150

    enum Key {
        static let trackId = "currentTrackId"
        static let isPlaying = "isPlaying"
        static let title = "trackTitle"
        static let artist = "trackArtist"
        static let artworkURL = "artworkURL"
        static let heartbeat = "lastHeartbeat"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    struct PlaybackSnapshot {
        var trackId: String?
        var isPlaying: Bool
        var title: String?
        var artist: String?
        var artworkURL: String?
        var heartbeat: Date?

        var heartbeatFresh: Bool {
            guard let hb = heartbeat else { return false }
            return Date().timeIntervalSince(hb) < heartbeatFreshInterval
        }

        var hasTrack: Bool { trackId != nil }
    }

    static func snapshot() -> PlaybackSnapshot {
        let d = defaults
        let hb: Date? = {
            let t = d.double(forKey: Key.heartbeat)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }()
        return PlaybackSnapshot(
            trackId: d.string(forKey: Key.trackId),
            isPlaying: d.bool(forKey: Key.isPlaying),
            title: d.string(forKey: Key.title),
            artist: d.string(forKey: Key.artist),
            artworkURL: d.string(forKey: Key.artworkURL),
            heartbeat: hb
        )
    }

    /// Write full playback state; always stamps a fresh heartbeat.
    static func write(trackId: String?, isPlaying: Bool, title: String?, artist: String?, artworkURL: String?) {
        let d = defaults
        if let trackId { d.set(trackId, forKey: Key.trackId) } else { d.removeObject(forKey: Key.trackId) }
        d.set(isPlaying, forKey: Key.isPlaying)
        if let title { d.set(title, forKey: Key.title) } else { d.removeObject(forKey: Key.title) }
        if let artist { d.set(artist, forKey: Key.artist) } else { d.removeObject(forKey: Key.artist) }
        if let artworkURL { d.set(artworkURL, forKey: Key.artworkURL) } else { d.removeObject(forKey: Key.artworkURL) }
        d.set(Date().timeIntervalSince1970, forKey: Key.heartbeat)
    }

    static func writeHeartbeat() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.heartbeat)
    }

    /// Reset to a stopped state (used on cold start so a stale `true` never lingers).
    static func reset() {
        write(trackId: nil, isPlaying: false, title: nil, artist: nil, artworkURL: nil)
    }

    // MARK: - Artwork cache (shared container)

    static func safeFileName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }

    static func artworkCacheURL(trackId: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("artwork-\(safeFileName(trackId)).jpg")
    }

    static func cachedArtwork(trackId: String) -> Data? {
        guard let url = artworkCacheURL(trackId: trackId) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func cacheArtwork(_ data: Data, trackId: String) {
        guard let url = artworkCacheURL(trackId: trackId) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
