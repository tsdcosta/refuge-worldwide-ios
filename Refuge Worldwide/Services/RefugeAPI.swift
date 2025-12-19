//
//  RefugeAPI.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import Foundation

final class RefugeAPI {
    static let shared = RefugeAPI()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]

            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback without milliseconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(dateString)"
            )
        }
        return d
    }()

    func fetchSchedule() async throws -> [ShowItem] {
        let url = URL(string: "https://refugeworldwide.com/api/schedule")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(ScheduleResponse.self, from: data)
        return response.schedule
    }

    func fetchLiveNow() async throws -> ShowItem? {
        let url = URL(string: "https://refugeworldwide.com/api/schedule")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer() // get the container
            let dateStr = try container.decode(String.self)    // decode the string

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: dateStr) {
                return date
            }

            // fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateStr) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date string: \(dateStr)"
            )
        }

        let response = try decoder.decode(ScheduleResponse.self, from: data)

        guard let liveNow = response.liveNow else {
            print("No liveNow data returned")
            return nil
        }

        return ShowItem(
            title: liveNow.title ?? "Live",
            slug: liveNow.slug ?? UUID().uuidString,
            date: nil,
            dateEnd: nil,
            coverImage: {
                if let urlString = liveNow.artwork, let url = URL(string: urlString) {
                    return ShowItem.CoverImage(url: url)
                }
                return nil
            }(),
            description: liveNow.description,
            genres: liveNow.genres,
            artistsCollection: liveNow.artistsCollection
        )
    }

    func fetchArtist(slug: String) async throws -> ArtistResponse {
        let urlString = "https://refugeworldwide.com/api/artists/\(slug)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ArtistResponse.self, from: data)
    }

    // Fetch detailed show information from the website API (/api/shows/<slug>)
    func fetchShowDetail(slug: String) async throws -> ShowDetail {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let urlString = "https://refugeworldwide.com/api/shows/\(encoded)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse wrapper JSON: { show: { ... } }
        let jsonAny = try JSONSerialization.jsonObject(with: data)
        guard let root = jsonAny as? [String: Any], let showDict = root["show"] as? [String: Any] else {
            // Fallback: try decoding directly
            return try decoder.decode(ShowDetail.self, from: data)
        }

        // description from top-level field
        let description = showDict["description"] as? String

        // genres from genresCollection.items[].name
        var genres: [String]? = nil
        if let genresCollection = showDict["genresCollection"] as? [String: Any],
           let items = genresCollection["items"] as? [[String: Any]] {
            let g = items.compactMap { $0["name"] as? String }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !g.isEmpty { genres = g }
        }

        // coverImage.url
        var coverImage: ShowDetail.CoverImage? = nil
        if let cover = showDict["coverImage"] as? [String: Any], let urlStr = cover["url"] as? String, let url = URL(string: urlStr) {
            coverImage = ShowDetail.CoverImage(url: url)
        }

        // artistsCollection
        var artistsCollection: ShowDetail.ArtistCollection? = nil
        if let artists = showDict["artistsCollection"] as? [String: Any], let items = artists["items"] as? [[String: Any]] {
            let a = items.compactMap { item -> ShowDetail.Artist? in
                guard let name = item["name"] as? String else { return nil }
                let slug = item["slug"] as? String ?? ""
                return ShowDetail.Artist(name: name, slug: slug)
            }
            if !a.isEmpty { artistsCollection = ShowDetail.ArtistCollection(items: a) }
        }

        // Try to extract paragraphs from content.json -> content -> [ { content: [ { content: [ { value } ] } ] } ]
        var descriptionParagraphs: [String]? = nil
        if let content = showDict["content"] as? [String: Any], let json = content["json"] as? [String: Any], let blocks = json["content"] as? [[String: Any]] {
            var paras: [String] = []
            for block in blocks {
                if let inner = block["content"] as? [[String: Any]] {
                    var pieces: [String] = []
                    for piece in inner {
                        if let inner2 = piece["content"] as? [[String: Any]] {
                            for leaf in inner2 {
                                if let value = leaf["value"] as? String {
                                    pieces.append(value)
                                }
                            }
                        } else if let value = piece["value"] as? String {
                            pieces.append(value)
                        }
                    }
                    let para = pieces.joined()
                    let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { paras.append(trimmed) }
                }
            }
            if !paras.isEmpty { descriptionParagraphs = paras }
        }

        // Fallback: split description by newlines
        if descriptionParagraphs == nil, let desc = description {
            let parts = desc.components(separatedBy: CharacterSet.newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !parts.isEmpty { descriptionParagraphs = parts }
        }

        // relatedShows array (at root level, not inside show)
        var relatedShows: [ShowDetail.RelatedShow]? = nil
        if let related = root["relatedShows"] as? [[String: Any]] {
            let shows = related.compactMap { item -> ShowDetail.RelatedShow? in
                guard let id = item["id"] as? String,
                      let title = item["title"] as? String,
                      let slug = item["slug"] as? String else { return nil }
                let date = item["date"] as? String
                let mixcloudLink = item["mixcloudLink"] as? String
                let coverImage = item["coverImage"] as? String
                let genres = item["genres"] as? [String]
                // Parse artistsCollection for related shows
                var relatedArtists: ShowDetail.ArtistCollection? = nil
                if let artists = item["artistsCollection"] as? [String: Any], let items = artists["items"] as? [[String: Any]] {
                    let a = items.compactMap { artistItem -> ShowDetail.Artist? in
                        guard let name = artistItem["name"] as? String else { return nil }
                        let artistSlug = artistItem["slug"] as? String ?? ""
                        return ShowDetail.Artist(name: name, slug: artistSlug)
                    }
                    if !a.isEmpty { relatedArtists = ShowDetail.ArtistCollection(items: a) }
                }
                return ShowDetail.RelatedShow(id: id, title: title, date: date, slug: slug, mixcloudLink: mixcloudLink, coverImage: coverImage, genres: genres, artistsCollection: relatedArtists)
            }
            if !shows.isEmpty { relatedShows = shows }
        }

        // Try to extract a top-level mixcloud link from the show object
        let mixcloudLink: String? = showDict["mixcloudLink"] as? String

        return ShowDetail(description: description, genres: genres, coverImage: coverImage, artistsCollection: artistsCollection, descriptionParagraphs: descriptionParagraphs, relatedShows: relatedShows, mixcloudLink: mixcloudLink)
    }
}
