import Foundation

/// Fetches the Cosmic Jukebox playlist from the Cloudflare Worker.
enum PlaylistService {
    static let playlistURL = URL(
        string: "https://mg-cosmic-jukebox-manager.mikegyver.workers.dev/api/playlist"
    )!

    enum FetchError: Error, LocalizedError {
        case badStatus(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Playlist request failed (HTTP \(code))."
            case .empty: return "The playlist came back empty."
            }
        }
    }

    static func fetch() async throws -> [Track] {
        var req = URLRequest(url: playlistURL, timeoutInterval: 30)
        req.setValue("CosmicJukebox-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw FetchError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let tracks = try JSONDecoder().decode(PlaylistResponse.self, from: data).tracks
        guard !tracks.isEmpty else { throw FetchError.empty }
        return tracks
    }
}
