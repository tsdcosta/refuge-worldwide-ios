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

    /// Call when a view appears that needs live show data
    func addObserver() {
        activeObservers += 1
        if activeObservers == 1 {
            startRefreshTimer()
        }
    }

    /// Call when a view disappears
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

            // Only update if show changed (different slug = different show)
            let showChanged = newShow?.slug != liveShow?.slug

            if showChanged {
                liveShow = newShow

                // Reset description/genres when show changes
                liveDescription = []
                liveGenres = []
            }

            // Fetch show details (description, genres)
            if let slug = newShow?.slug {
                do {
                    let detail = try await RefugeAPI.shared.fetchShowDetail(slug: slug)

                    let newGenres = detail.genres?.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty } ?? []

                    let newDescription: [String]
                    if let paragraphs = detail.descriptionParagraphs, !paragraphs.isEmpty {
                        newDescription = paragraphs
                    } else if let text = detail.description {
                        newDescription = splitIntoParagraphs(text)
                    } else {
                        newDescription = []
                    }

                    // Update only if changed
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

            // Update Now Playing if live stream is active
            if let show = liveShow {
                updateNowPlayingMetadata(show: show)
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

        var timeString = ""
        if let start = show.date, let end = show.dateEnd {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            timeString = "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = show.date {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            timeString = formatter.string(from: start)
        }

        radio.updateNowPlayingInfo(
            title: show.title,
            subtitle: timeString,
            artworkURL: show.coverImage?.url
        )
    }
}
