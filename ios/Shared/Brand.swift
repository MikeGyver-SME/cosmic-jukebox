import SwiftUI

/// MikeGyver Studio navy + gold brand palette, shared by app and widget.
enum Brand {
    static let navy = Color(red: 0.04, green: 0.09, blue: 0.18)
    static let navyDeep = Color(red: 0.01, green: 0.04, blue: 0.10)
    static let gold = Color(red: 0.91, green: 0.72, blue: 0.29)
    static let goldSoft = Color(red: 0.95, green: 0.82, blue: 0.45)
    static let ink = Color(red: 0.90, green: 0.94, blue: 1.0)
    static let muted = Color(red: 0.58, green: 0.71, blue: 0.81)

    /// Deep-space gradient used behind lists and the widget.
    static var background: some View {
        LinearGradient(
            colors: [navy, navyDeep],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
