import AVFoundation
import Combine
import MediaPlayer
import UIKit
import WidgetKit

/// Owns AVPlayer streaming, lock-screen / CarPlay Now Playing metadata,
/// remote-command handling, and syncing playback state to the App Group
/// so the Home Screen widget stays current.
final class PlayerEngine: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published var isLoadingPlaylist = false
    @Published var errorMessage: String?
    /// One-line diagnostic: App Group reachability + last state synced to it.
    @Published private(set) var syncDebug: String = "starting…"

    private var player: AVPlayer?
    private var heartbeatTimer: Timer?
    private var endObserver: NSObjectProtocol?
    private var toggleObserverAdded = false

    // MARK: - Lifecycle

    /// Call once from the app entry point.
    func start() {
        // A stale `isPlaying=true` from a killed session must never linger.
        JukeboxShared.reset()
        // Keep the change-detection mirrors consistent with the reset state.
        lastSyncedTrackId = nil
        lastSyncedIsPlaying = false
        lastSyncedArtworkURL = nil
        updateSyncDebug()
        // Make sure the widget drops any stale entry from the dead session.
        WidgetCenter.shared.reloadAllTimelines()
        setupAudioSession()
        setupRemoteCommands()
        observeWidgetToggle()
        observeAppState()
        startHeartbeat()
        Task { await loadPlaylist() }
    }

    deinit {
        heartbeatTimer?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Playlist

    @MainActor
    func loadPlaylist() async {
        isLoadingPlaylist = true
        errorMessage = nil
        defer { isLoadingPlaylist = false }
        do {
            tracks = try await PlaylistService.fetch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transport

    func play(_ track: Track) {
        guard let url = track.audio else {
            errorMessage = "That track has no audio URL."
            return
        }
        if current?.id == track.id, player != nil {
            resume()
            return
        }
        stopCurrentItem()
        current = track
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.next() }
        player = AVPlayer(playerItem: item)
        resume()
    }

    func toggle() {
        if isPlaying {
            pause()
        } else if current != nil {
            resume()
        } else if let first = tracks.first {
            play(first)
        }
    }

    /// Used by the `cosmicjukebox://play` deep link.
    func ensurePlaying() {
        if !isPlaying { toggle() }
    }

    func pause() {
        player?.pause()
        setPlaying(false)
    }

    func resume() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback attempt still goes ahead.
        }
        player?.play()
        setPlaying(true)
    }

    func next() {
        guard !tracks.isEmpty else { return }
        let idx: Int
        if let cur = current, let i = tracks.firstIndex(of: cur) {
            idx = (i + 1) % tracks.count
        } else {
            idx = 0
        }
        play(tracks[idx])
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if let cur = current, let i = tracks.firstIndex(of: cur) {
            play(tracks[(i - 1 + tracks.count) % tracks.count])
        } else if let first = tracks.first {
            play(first)
        }
    }

    private func stopCurrentItem() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        syncSharedState()
        updateNowPlaying()
    }

    // MARK: - Shared state + widget refresh

    /// Mirrors of the last values written to the App Group. The widget only
    /// refreshes when something it displays actually changed — blindly
    /// reloading on every setPlaying burned WidgetKit's reload budget and
    /// let real changes get lost behind throttled/dropped refreshes.
    private var lastSyncedTrackId: String?
    private var lastSyncedIsPlaying = false
    private var lastSyncedArtworkURL: String?

    private func updateSyncDebug() {
        syncDebug = "group:\(JukeboxShared.groupReachable ? "OK" : "NO")"
            + " track:\(lastSyncedTrackId ?? "-")"
            + " playing:\(lastSyncedIsPlaying)"
    }

    private func syncSharedState() {
        let trackId = current?.id
        let playing = isPlaying
        let artworkURL = current?.artwork?.absoluteString
        guard trackId != lastSyncedTrackId
                || playing != lastSyncedIsPlaying
                || artworkURL != lastSyncedArtworkURL else { return }
        lastSyncedTrackId = trackId
        lastSyncedIsPlaying = playing
        lastSyncedArtworkURL = artworkURL
        updateSyncDebug()
        JukeboxShared.write(
            trackId: trackId,
            isPlaying: playing,
            title: current?.title,
            artist: current?.artist,
            artworkURL: artworkURL
        )
        JukeboxShared.postDarwin(JukeboxShared.stateNotification)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        JukeboxShared.writeHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            JukeboxShared.writeHeartbeat()
        }
    }

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in JukeboxShared.writeHeartbeat() }
    }

    // MARK: - Widget intent bridge (Darwin notification)

    private static let toggleCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let engine = Unmanaged<PlayerEngine>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async { engine.toggle() }
    }

    private func observeWidgetToggle() {
        guard !toggleObserverAdded else { return }
        toggleObserverAdded = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.toggleCallback,
            JukeboxShared.toggleNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session failed: \(error.localizedDescription)"
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
            else { return }
            if type == .began {
                self.pause()
            } else if type == .ended,
                      let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                      AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
                self.resume()
            }
        }
    }

    // MARK: - Now Playing (lock screen + CarPlay)

    /// In-memory artwork by track id. Seeded from the shared-container cache
    /// (which the widget extension also feeds), so cover art survives app
    /// restarts and the two processes share each download.
    private var artworkImages: [String: UIImage] = [:]
    private var artworkTask: Task<Void, Never>?
    /// Track id whose artwork is currently published (or being fetched).
    private var publishedArtworkTrackId: String?

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in
            self?.resume(); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle(); return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(); return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous(); return .success
        }
    }

    private func updateNowPlaying() {
        // Merge into the existing info dict. Rebuilding it from scratch on
        // every pause/resume/track-change was the CarPlay bug: it wiped the
        // artwork each time and the cover only came back if the re-download
        // won the race — otherwise CarPlay sat on the default art.
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let t = current {
            info[MPMediaItemPropertyTitle] = t.title
            info[MPMediaItemPropertyArtist] = t.artist
            if let album = t.albumTitle, !album.isEmpty {
                info[MPMediaItemPropertyAlbumTitle] = album
            } else {
                info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
            }
            if let img = cachedArtworkImage(for: t) {
                // Cached: publish instantly, no blank-art gap.
                info[MPMediaItemPropertyArtwork] =
                    MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                publishedArtworkTrackId = t.id
            } else if publishedArtworkTrackId != t.id {
                // New track with no cached art yet: clear the previous
                // track's cover (never show the wrong one) and fetch in
                // the background; the fetch re-publishes on arrival.
                info.removeValue(forKey: MPMediaItemPropertyArtwork)
                publishedArtworkTrackId = t.id
                fetchArtwork(for: t)
            }
            // Same track, art still downloading: leave the dict untouched.
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
            publishedArtworkTrackId = nil
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func cachedArtworkImage(for track: Track) -> UIImage? {
        if let img = artworkImages[track.id] { return img }
        if let data = JukeboxShared.cachedArtwork(trackId: track.id),
           let img = UIImage(data: data) {
            artworkImages[track.id] = img
            return img
        }
        return nil
    }

    private func fetchArtwork(for track: Track) {
        artworkTask?.cancel()
        guard let artURL = track.artwork else { return }
        let trackId = track.id
        artworkTask = Task { [weak self] in
            guard let self else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: artURL),
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }
            // Share the bytes with the widget extension too.
            JukeboxShared.cacheArtwork(data, trackId: trackId)
            await MainActor.run {
                self.artworkImages[trackId] = image
                // Only publish if this is still the current track.
                if self.current?.id == trackId {
                    self.updateNowPlaying()
                    // The widget reads art from the shared cache, so give it
                    // a refresh now that the new cover is available.
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
}
