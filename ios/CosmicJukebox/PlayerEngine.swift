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

    private var player: AVPlayer?
    private var heartbeatTimer: Timer?
    private var endObserver: NSObjectProtocol?
    private var toggleObserverAdded = false

    // MARK: - Lifecycle

    /// Call once from the app entry point.
    func start() {
        // A stale `isPlaying=true` from a killed session must never linger.
        JukeboxShared.reset()
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

    private func syncSharedState() {
        JukeboxShared.write(
            trackId: current?.id,
            isPlaying: isPlaying,
            title: current?.title,
            artist: current?.artist,
            artworkURL: current?.artwork?.absoluteString
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
        var info: [String: Any] = [:]
        if let t = current {
            info[MPMediaItemPropertyTitle] = t.title
            info[MPMediaItemPropertyArtist] = t.artist
            if let album = t.albumTitle, !album.isEmpty {
                info[MPMediaItemPropertyAlbumTitle] = album
            }
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // Artwork arrives async; refresh the info dict when it lands.
        if let artURL = current?.artwork {
            Task { [weak self] in
                guard let self else { return }
                if let data = try? await URLSession.shared.data(from: artURL).0,
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        // Only apply if this is still the current track.
                        guard self.current?.artwork == artURL else { return }
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        }
    }
}
