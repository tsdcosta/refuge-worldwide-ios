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
    let nextUp: [ShowItem]?        // optional, may be absent for last show of day
    let schedule: [ShowItem]?      // optional, may be absent for last show of day
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
    let descriptionParagraphs: [String]?
    let relatedShows: [RelatedShow]?
    let mixcloudLink: String?      // optional mixcloud link for the show

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

    struct RelatedShow: Decodable, Identifiable {
        let id: String
        let title: String
        let date: String?
        let slug: String
        let mixcloudLink: String?
        let coverImage: String?
        let genres: [String]?
        let artistsCollection: ArtistCollection?

        var coverImageURL: URL? {
            guard let coverImage = coverImage else { return nil }
            return URL(string: coverImage)
        }
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

    /// Memberwise initializer
    init(title: String, slug: String, date: Date?, dateEnd: Date?, coverImage: CoverImage?, description: String?, genres: [String]?, artistsCollection: ArtistCollection?) {
        self.title = title
        self.slug = slug
        self.date = date
        self.dateEnd = dateEnd
        self.coverImage = coverImage
        self.description = description
        self.genres = genres
        self.artistsCollection = artistsCollection
    }

    /// Create a ShowItem from a RelatedShow (for navigation)
    init(from relatedShow: ShowDetail.RelatedShow) {
        self.title = relatedShow.title
        self.slug = relatedShow.slug
        self.dateEnd = nil
        self.description = nil
        self.genres = relatedShow.genres
        self.artistsCollection = nil

        // Parse date from ISO string
        if let dateStr = relatedShow.date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: dateStr) {
                self.date = parsed
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                self.date = formatter.date(from: dateStr)
            }
        } else {
            self.date = nil
        }

        // Parse coverImage URL
        if let urlStr = relatedShow.coverImage, let url = URL(string: urlStr) {
            self.coverImage = CoverImage(url: url)
        } else {
            self.coverImage = nil
        }
    }

    /// Create a ShowItem from an ArtistShow (for navigation)
    init(from artistShow: ArtistResponse.ArtistShow) {
        self.title = artistShow.title
        self.slug = artistShow.slug
        self.dateEnd = nil
        self.description = nil
        self.genres = artistShow.genres
        self.artistsCollection = nil

        // Parse date from ISO string
        if let dateStr = artistShow.date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: dateStr) {
                self.date = parsed
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                self.date = formatter.date(from: dateStr)
            }
        } else {
            self.date = nil
        }

        // Parse coverImage URL
        if let url = artistShow.coverImageURL {
            self.coverImage = CoverImage(url: url)
        } else {
            self.coverImage = nil
        }
    }

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

// MARK: - Artist List Item (for artist listing)

struct ArtistListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let isResident: Bool
    let photoURL: URL?
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
