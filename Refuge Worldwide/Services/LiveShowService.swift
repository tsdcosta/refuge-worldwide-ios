//
//  LiveShowService.swift
//  Refuge Worldwide
//
//  Caches live show data to prevent UI flicker on view transitions.
//

import Foundation
import Combine

@MainActor
final class LiveShowService: ObservableObject {
    static let shared = LiveShowService()

    @Published private(set) var liveShow: ShowItem?
    @Published private(set) var liveDescription: [String] = []
    @Published private(set) var liveGenres: [String] = []
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?
    private var activeObservers = 0

    private init() {}

    // MARK: - Observer Management

    func addObserver() {
        activeObservers += 1
        if activeObservers == 1 {
            startRefreshTimer()
        }
    }

    func removeObserver() {
        activeObservers = max(0, activeObservers - 1)
        if activeObservers == 0 {
            stopRefreshTimer()
        }
    }

    // MARK: - Data Fetching

    /// Fetches live show data. Updates cache only if data changed.
    func refresh() async {
        // Don't show loading state if we already have cached data
        if liveShow == nil {
            isLoading = true
        }

        do {
            var newShow = try await RefugeAPI.shared.fetchLiveNow()

            // Hydrate with full schedule data for artistsCollection
            if let showID = newShow?.id {
                do {
                    let schedule = try await RefugeAPI.shared.fetchSchedule()
                    if let fullShow = schedule.first(where: { $0.id == showID }) {
                        newShow = fullShow
                    }
                } catch {
                    print("[LiveShowService] Failed to hydrate from schedule:", error)
                }
            }

            let showChanged = newShow?.slug != liveShow?.slug

            if showChanged {
                liveShow = newShow
                liveDescription = []
                liveGenres = []

                if let show = newShow {
                    updateNowPlayingMetadata(show: show)
                }
            }

            // Fetch show details (description, genres)
            if let slug = newShow?.slug {
                do {
                    let detail = try await RefugeAPI.shared.fetchShowDetail(slug: slug)

                    let newGenres = detail.genres?.filter { !$0.isEmpty } ?? []

                    let newDescription: [String]
                    if let paragraphs = detail.descriptionParagraphs, !paragraphs.isEmpty {
                        newDescription = paragraphs
                    } else if let text = detail.description {
                        newDescription = splitIntoParagraphs(text)
                    } else {
                        newDescription = []
                    }

                    if newGenres != liveGenres {
                        liveGenres = newGenres
                    }
                    if newDescription != liveDescription {
                        liveDescription = newDescription
                    }
                } catch {
                    print("[LiveShowService] Failed to fetch show detail:", error)
                }
            }
        } catch {
            print("[LiveShowService] Failed to fetch live show:", error)
        }

        isLoading = false
    }

    // MARK: - Private Helpers

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateNowPlayingMetadata(show: ShowItem) {
        let radio = RadioPlayer.shared
        guard radio.isLiveStream else { return }

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        var timeString = ""
        if let start = show.date, let end = show.dateEnd {
            timeString = "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = show.date {
            timeString = formatter.string(from: start)
        }

        radio.updateNowPlayingInfo(
            title: show.title,
            subtitle: timeString,
            artworkURL: show.coverImage?.url
        )
    }
}
