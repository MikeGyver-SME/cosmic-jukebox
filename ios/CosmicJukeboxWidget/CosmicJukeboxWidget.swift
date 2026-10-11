import SwiftUI
import WidgetKit

/// Refresh the widget whenever the app posts a playback-state change.
private func jukeboxStateChanged(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    WidgetCenter.shared.reloadAllTimelines()
}

@main
struct CosmicJukeboxWidgetBundle: WidgetBundle {
    init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            jukeboxStateChanged,
            JukeboxShared.stateNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    var body: some Widget {
        JukeboxWidget()
    }
}
