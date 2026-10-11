import SwiftUI

/// Compact transport bar pinned above the tab bar area.
struct NowPlayingBar: View {
    @EnvironmentObject private var engine: PlayerEngine

    var body: some View {
        if let track = engine.current {
            VStack(spacing: 0) {
                Divider().background(Brand.gold.opacity(0.3))
                HStack(spacing: 12) {
                    AsyncImage(url: track.artwork) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Brand.navy)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundStyle(Brand.gold)
                                )
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.ink)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundStyle(Brand.gold)
                    }
                    Button { engine.toggle() } label: {
                        Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Brand.gold)
                    }
                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundStyle(Brand.gold)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Brand.navyDeep.opacity(0.92))
            }
        }
    }
}
