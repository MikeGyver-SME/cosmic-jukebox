import SwiftUI
import WidgetKit

struct JukeboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "studio.mikegyver.cosmicjukebox.widget",
            provider: JukeboxProvider()
        ) { entry in
            JukeboxWidgetView(entry: entry)
        }
        .configurationDisplayName("Cosmic Jukebox")
        .description("Play or pause Mike's cosmic jukebox from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct JukeboxWidgetView: View {
    let entry: JukeboxEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Brand.navy, Brand.navyDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            content
        }
        // Tapping anywhere else opens the app.
        .widgetURL(URL(string: "cosmicjukebox://nowplaying"))
    }

    @ViewBuilder
    private var content: some View {
        let snap = entry.snapshot
        if family == .systemSmall {
            VStack(spacing: 8) {
                artwork(size: 64)
                Text(snap.title ?? "Cosmic Jukebox")
                    .font(.headline)
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(snap.artist ?? "MikeGyver Studio")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                playButton
            }
            .padding()
        } else {
            HStack(spacing: 12) {
                artwork(size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MIKEGYVER STUDIO")
                        .font(.caption2.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(Brand.gold)
                    Text(snap.title ?? "Cosmic Jukebox")
                        .font(.headline)
                        .foregroundStyle(Brand.ink)
                        .lineLimit(2)
                    Text(snap.artist ?? "MikeGyver Studio")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    statusLine
                }
                Spacer()
                playButton
            }
            .padding()
        }
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let data = entry.artworkData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.navy)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundStyle(Brand.gold)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Brand.gold.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusLine: some View {
        let snap = entry.snapshot
        if !snap.hasTrack {
            Text("Tap play to start the music")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        } else if snap.heartbeatFresh {
            Text(snap.isPlaying ? "Now playing" : "Paused")
                .font(.caption)
                .foregroundStyle(Brand.goldSoft)
        } else {
            Text("Tap play to open the app")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
    }

    /// The play/pause control. Fresh heartbeat → AppIntent (no app launch).
    /// Stale heartbeat → Link that opens the app and toggles there.
    @ViewBuilder
    private var playButton: some View {
        let snap = entry.snapshot
        let icon = snap.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        if snap.heartbeatFresh {
            Button(intent: TogglePlayPauseIntent()) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Brand.gold)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "cosmicjukebox://toggle")!) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Brand.gold)
            }
        }
    }
}
