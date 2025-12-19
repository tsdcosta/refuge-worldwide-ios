//
//  ShowItem.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import Foundation

struct ScheduleResponse: Decodable {
    let status: String
    let liveNow: LiveNow?          // optional, all fields optional
    let nextUp: [ShowItem]
    let schedule: [ShowItem]
}

struct LiveNow: Decodable {
    let title: String?
    let slug: String?
    let artwork: String?           // string from API
    let description: String?
    let genres: [String]?
    let artistsCollection: ShowItem.ArtistCollection?
}

struct ShowDetail: Decodable {
    let description: String?
    let genres: [String]?
    let coverImage: CoverImage?
    let artistsCollection: ArtistCollection?
    
    struct CoverImage: Decodable {
        let url: URL
    }

    struct ArtistCollection: Decodable {
        let items: [Artist]
    }

    struct Artist: Decodable {
        let name: String
        let slug: String
    }
}

struct ShowItem: Identifiable, Decodable, Hashable {
    var id: String { slug }

    let title: String
    let slug: String
    let date: Date?
    let dateEnd: Date?
    let coverImage: CoverImage?
    let description: String?
    let genres: [String]?
    let artistsCollection: ArtistCollection?

    /// Returns true if this show is currently live (now is between date and dateEnd)
    var isLiveNow: Bool {
        guard let start = date, let end = dateEnd else { return false }
        let now = Date()
        return now >= start && now < end
    }

    struct CoverImage: Decodable, Hashable {
        let url: URL
    }

    struct ArtistCollection: Decodable, Hashable {
        let items: [Artist]
    }

    struct Artist: Decodable, Identifiable, Hashable {
        var id: String { slug }
        let name: String
        let slug: String
    }
}

// MARK: - Artist Detail Response

struct ArtistResponse: Decodable {
    let name: String
    let slug: String
    let description: String?
    let photo: ArtistPhoto?
    let shows: [ArtistShow]?

    struct ArtistPhoto: Decodable {
        let url: URL
        let title: String?
        let description: String?
    }

    struct ArtistShow: Decodable, Identifiable {
        let id: String
        let title: String
        let date: String?
        let slug: String
        let mixcloudLink: String?
        let coverImage: String?  // API returns string URL directly
        let genres: [String]?

        var coverImageURL: URL? {
            guard let coverImage = coverImage else { return nil }
            return URL(string: coverImage)
        }
    }
}
