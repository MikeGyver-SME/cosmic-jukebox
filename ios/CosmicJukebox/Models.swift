import Foundation

/// A track from the Cosmic Jukebox playlist API.
struct Track: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let eyebrow: String?
    let description: String?
    let audio: URL?
    let artwork: URL?
    let albumTitle: String?
    let trackNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, eyebrow, description, audio, artwork
        case albumTitle, trackNumber
    }
}

extension Track: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Unknown track"
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? "MikeGyver Studio"
        eyebrow = try? c.decodeIfPresent(String.self, forKey: .eyebrow)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        if let s = try? c.decodeIfPresent(String.self, forKey: .audio) {
            audio = URL(string: s)
        } else {
            audio = nil
        }
        if let s = try? c.decodeIfPresent(String.self, forKey: .artwork) {
            artwork = URL(string: s)
        } else {
            artwork = nil
        }
        albumTitle = try? c.decodeIfPresent(String.self, forKey: .albumTitle)
        // trackNumber may arrive as Int or String in the wild; be lenient.
        if let n = try? c.decodeIfPresent(Int.self, forKey: .trackNumber) {
            trackNumber = n
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .trackNumber) {
            trackNumber = Int(s)
        } else {
            trackNumber = nil
        }
    }
}

struct PlaylistResponse: Decodable {
    let jukeboxTitle: String?
    let tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case jukeboxTitle, tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jukeboxTitle = try? c.decodeIfPresent(String.self, forKey: .jukeboxTitle)
        tracks = (try? c.decodeIfPresent([Track].self, forKey: .tracks)) ?? []
    }
}
