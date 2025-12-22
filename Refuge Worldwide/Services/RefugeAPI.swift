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
            
            // Fallback to date-only format
            formatter.formatOptions = [.withFullDate]
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
        return response.schedule ?? []
    }

    func fetchLiveNow() async throws -> ShowItem? {
        let url = URL(string: "https://refugeworldwide.com/api/schedule")!
        let (data, _) = try await URLSession.shared.data(from: url)
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

    func searchArtists(query: String) async throws -> [ArtistListItem] {
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://refugeworldwide.com/api/search?query=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artistsArray = json["artists"] as? [[String: Any]] else {
            return []
        }

        return artistsArray.compactMap { item -> ArtistListItem? in
            guard let fields = item["fields"] as? [String: Any],
                  let sys = item["sys"] as? [String: Any],
                  let id = sys["id"] as? String,
                  let name = fields["name"] as? String,
                  let slug = fields["slug"] as? String else {
                return nil
            }

            var photoURL: URL? = nil
            if let photo = fields["photo"] as? [String: Any],
               let photoFields = photo["fields"] as? [String: Any],
               let file = photoFields["file"] as? [String: Any],
               let urlStr = file["url"] as? String {
                photoURL = URL(string: "https:\(urlStr)")
            }

            // Search doesn't return isResident, default to false
            return ArtistListItem(id: id, name: name, slug: slug, isResident: false, photoURL: photoURL)
        }
    }

    func searchShows(query: String) async throws -> [ShowItem] {
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://refugeworldwide.com/api/search?query=\(encoded)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let showsArray = json["shows"] as? [[String: Any]] else {
            return []
        }

        return showsArray.compactMap { item -> ShowItem? in
            guard let _ = item["id"] as? String,
                  let title = item["title"] as? String,
                  let slug = item["slug"] as? String else {
                return nil
            }

            var coverImage: ShowItem.CoverImage? = nil
            if let urlStr = item["coverImage"] as? String {
                // API returns protocol-relative URLs like //images.ctfassets.net/...
                let fullUrlStr = urlStr.hasPrefix("//") ? "https:\(urlStr)" : urlStr
                if let url = URL(string: fullUrlStr) {
                    coverImage = ShowItem.CoverImage(url: url)
                }
            }

            var date: Date? = nil
            if let dateStr = item["date"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: dateStr)
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: dateStr)
                }
                if date == nil {  // date only
                    formatter.formatOptions = [.withFullDate]
                    date = formatter.date(from: dateStr)
                }
            }

            let genres = item["genres"] as? [String]

            return ShowItem(
                title: title,
                slug: slug,
                date: date,
                dateEnd: nil,
                coverImage: coverImage,
                description: nil,
                genres: genres,
                artistsCollection: nil
            )
        }
    }


    func fetchArtists(isResident: Bool, limit: Int, skip: Int) async throws -> [ArtistListItem] {
        let urlString = "https://refugeworldwide.com/api/artists?role=\(isResident)&limit=\(limit)&skip=\(skip)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse the JSON array manually since the structure is nested
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return jsonArray.compactMap { item -> ArtistListItem? in
            guard let sys = item["sys"] as? [String: Any],
                  let id = sys["id"] as? String,
                  let name = item["name"] as? String,
                  let slug = item["slug"] as? String else {
                return nil
            }

            let isResident = item["isResident"] as? Bool ?? false

            var photoURL: URL? = nil
            if let photo = item["photo"] as? [String: Any],
               let urlStr = photo["url"] as? String {
                photoURL = URL(string: "\(urlStr)")
            }

            return ArtistListItem(id: id, name: name, slug: slug, isResident: isResident, photoURL: photoURL)
        }
    }

    func fetchGenres() async throws -> [String] {
        let url = URL(string: "https://refugeworldwide.com/api/genres")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    func fetchShowsByGenre(genre: String, take: Int = 20, skip: Int = 0) async throws -> [ShowItem] {
        var components = URLComponents(string: "https://refugeworldwide.com/api/shows")!
        components.queryItems = [
            URLQueryItem(name: "take", value: String(take)),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "filter", value: genre)
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return jsonArray.compactMap { item -> ShowItem? in
            guard let title = item["title"] as? String,
                  let slug = item["slug"] as? String else {
                return nil
            }

            var coverImage: ShowItem.CoverImage? = nil
            if let urlStr = item["coverImage"] as? String {
                let fullUrlStr = urlStr.hasPrefix("//") ? "https:\(urlStr)" : urlStr
                if let url = URL(string: fullUrlStr) {
                    coverImage = ShowItem.CoverImage(url: url)
                }
            }

            var date: Date? = nil
            if let dateStr = item["date"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: dateStr)
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: dateStr)
                }
            }

            let genres = item["genres"] as? [String]

            return ShowItem(
                title: title,
                slug: slug,
                date: date,
                dateEnd: nil,
                coverImage: coverImage,
                description: nil,
                genres: genres,
                artistsCollection: nil
            )
        }
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
            let g = items.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
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
