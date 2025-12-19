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
}
