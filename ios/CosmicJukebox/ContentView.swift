import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine

    var body: some View {
        ZStack {
            Brand.background
            VStack(spacing: 0) {
                header
                if engine.isLoadingPlaylist {
                    Spacer()
                    ProgressView("Loading the jukebox…")
                        .tint(Brand.gold)
                    Spacer()
                } else if engine.tracks.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 44))
                            .foregroundStyle(Brand.gold)
                        Text(engine.errorMessage ?? "No tracks found.")
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Try again") {
                            Task { await engine.loadPlaylist() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.gold)
                        .foregroundStyle(Brand.navyDeep)
                    }
                    Spacer()
                } else {
                    trackList
                }
                NowPlayingBar()
                Text(engine.syncDebug)
                    .font(.caption2)
                    .foregroundStyle(Brand.muted.opacity(0.7))
                    .padding(.bottom, 2)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("MIKEGYVER STUDIO")
                .font(.caption2.weight(.bold))
                .tracking(3)
                .foregroundStyle(Brand.gold)
            Text("Cosmic Jukebox")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Brand.ink)
            Text("\(engine.tracks.count) tracks · streaming")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var trackList: some View {
        List(engine.tracks) { track in
            TrackRow(
                track: track,
                isCurrent: track.id == engine.current?.id,
                isPlaying: track.id == engine.current?.id && engine.isPlaying
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { engine.play(track) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.artwork) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.navy)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(Brand.gold)
                        )
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(isCurrent ? Brand.gold : Brand.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                if let album = track.albumTitle, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(Brand.muted.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer()
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(Brand.gold)
            } else if isCurrent {
                Image(systemName: "pause.circle")
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Brand.gold.opacity(0.08) : Color.clear)
        )
    }
}
