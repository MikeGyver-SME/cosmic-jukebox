# Cosmic Jukebox — iOS app + Home Screen widget

Streams Mike's songs from the Cosmic Jukebox playlist API
(`mg-cosmic-jukebox-manager.mikegyver.workers.dev`) with an AVPlayer engine,
lock-screen / CarPlay Now Playing metadata, and an interactive iOS 17+
Home Screen widget (tap to play, tap again to pause).

- App bundle ID: `studio.mikegyver.cosmicjukebox` · display name "Cosmic Jukebox"
- Widget extension: `studio.mikegyver.cosmicjukebox.widget`
- App Group: `group.studio.mikegyver.cosmicjukebox` (shared playback state)
- URL scheme: `cosmicjukebox://` (`toggle`, `play`)
- iOS 17+, SwiftUI, no third-party dependencies
- Distribution: **TestFlight** (Apple Developer account, CI-built IPA)

## The honest CarPlay note

Tapping the **CarPlay display itself cannot start playback** — Apple reserves
interactive in-car screens for approved audio apps holding the restricted
`com.apple.developer.carplay-audio` entitlement (granted case-by-case, not
available to TestFlight/sideloaded builds). What this app does instead:

1. Tap the **iPhone Home Screen widget** once → music starts on the phone.
2. Audio routes through the car speakers automatically (Bluetooth / wired CarPlay).
3. CarPlay's **Now Playing** screen picks up the track with artwork, title,
   and full transport controls (play / pause / next / previous) — no special
   entitlement needed for that.

So it's one tap on the phone, then everything else happens on the car display.

## One-time Apple Developer portal setup

Do this once before the first CI build:

1. **App IDs** — create (or let Xcode create) two App IDs:
   - `studio.mikegyver.cosmicjukebox`
   - `studio.mikegyver.cosmicjukebox.widget`
2. **App Group** — in *Certificates, Identifiers & Profiles → Identifiers*,
   register the App Group `group.studio.mikegyver.cosmicjukebox`, then edit
   **both** App IDs and enable the App Groups capability, ticking that group.
3. **Repo secrets** — same four as the PodMix repo
   (*Settings → Secrets and variables → Actions*):
   - `ASC_KEY_ID` — App Store Connect API key ID
   - `ASC_ISSUER_ID` — Issuer ID (UUID)
   - `ASC_KEY_P8` — full contents of the `AuthKey_XXXX.p8` file
   - `TEAM_ID` — Apple Developer Team ID

The CI (`sigh`) mints the distribution certificate and fetches one App Store
provisioning profile per bundle ID on every run, so nothing else needs manual
upkeep.

## Ship it

```bash
cd ~/workspace/cosmic-jukebox
git init
git add -A
git commit -m "Cosmic Jukebox v1.0.0: app + widget for TestFlight"
git branch -M main
git remote add origin <your-github-remote-url>
git push -u origin main
git tag v1.0.0
git push origin v1.0.0
```

Pushing the `v1.0.0` tag triggers `.github/workflows/testflight.yml`:
sigh (both bundle IDs) → xcodegen → manual-signing archive → export →
`pilot upload` to TestFlight. The IPA is also kept as a workflow artifact
for 14 days.

Bump versions in `ios/project.yml` (`MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION`) and tag again (e.g. `v1.0.1`) for the next build.

## How the widget talk works

- Shared state lives in the App Group UserDefaults: current track, isPlaying,
  title/artist/artwork URL, and a heartbeat the app refreshes every 60 s.
- **Widget → app:** the widget's `TogglePlayPauseIntent` flips `isPlaying` in
  shared defaults and posts the Darwin notification
  `studio.mikegyver.jukebox.toggle`; the app observes it and toggles AVPlayer.
- **App → widget:** every transport change posts
  `studio.mikegyver.jukebox.state` and calls
  `WidgetCenter.shared.reloadAllTimelines()`.
- **Fresh heartbeat (< 5 min):** the widget button runs the intent directly —
  no app launch. **Stale heartbeat** (app force-quit / reboot): the widget
  shows a `cosmicjukebox://toggle` Link instead, opening the app to toggle.

## Project layout

```
ios/
  project.yml                  # XcodeGen (hand-written Info.plists, manual signing)
  Shared/                      # compiled into BOTH targets
    SharedState.swift          # App Group state, Darwin helpers, artwork cache
    Brand.swift                # navy/gold palette
  CosmicJukebox/               # app target
    CosmicJukeboxApp.swift     # entry + cosmicjukebox:// URL handling
    Models.swift               # Track / PlaylistResponse (lenient decoding)
    PlaylistService.swift      # Worker playlist fetch
    PlayerEngine.swift         # AVPlayer, Now Playing, remote commands, widget bridge
    ContentView.swift          # track list
    NowPlayingBar.swift        # transport bar
    Info.plist                 # audio background mode, URL scheme (hand-written)
    CosmicJukebox.entitlements  # App Group
    Assets.xcassets/           # AppIcon (1024 PNG, no alpha) + BrandNavy
  CosmicJukeboxWidget/         # widget extension target
    CosmicJukeboxWidget.swift  # WidgetBundle + Darwin state observer
    JukeboxWidget.swift        # small + medium views, play/pause control
    WidgetProvider.swift       # timeline, artwork download + cache
    TogglePlayPauseIntent.swift# AppIntent (openAppWhenRun = false)
    Info.plist                 # widgetkit NSExtension (hand-written)
    CosmicJukeboxWidget.entitlements
.github/workflows/testflight.yml  # dual-profile TestFlight pipeline
```
