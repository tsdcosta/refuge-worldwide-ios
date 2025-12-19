//
//  LiveView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI
import SwiftSoup

struct LiveView: View {
    @ObservedObject private var radio = RadioPlayer.shared
    @State private var liveShow: ShowItem?
    @State private var liveDescription: [String] = []
    @State private var liveGenres: [String] = []
    @State private var navigationPath = NavigationPath()

    private var timeString: String {
        guard let show = liveShow else { return "" }
        if let start = show.date, let end = show.dateEnd {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = show.date {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: start)
        }
        return ""
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    // Cover image with live indicator overlay
                    ZStack(alignment: .topLeading) {
                        if let coverURL = liveShow?.coverImage?.url {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    AsyncImage(url: coverURL) { phase in
                                        switch phase {
                                        case .empty:
                                            Theme.cardBackground
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure(_):
                                            Theme.cardBackground
                                        @unknown default:
                                            Theme.cardBackground
                                        }
                                    }
                                )
                                .clipped()
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .background(Theme.cardBackground)
                        }

                        // Live indicator
                        if radio.isPlaying || radio.isBuffering {
                            LiveIndicator()
                                .padding(Theme.Spacing.base)
                        }
                    }

                    if let show = liveShow {
                        VStack(spacing: Theme.Spacing.base) {
                            // Title - serif heading style
                            Text(show.title)
                                .font(.serifHeading(size: Theme.Typography.headingBase))
                                .foregroundColor(Theme.foreground)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Theme.Spacing.lg)

                            // Time
                            if !timeString.isEmpty {
                                Text(timeString)
                                    .font(.lightBody(size: Theme.Typography.bodySmall))
                                    .foregroundColor(Theme.secondaryText)
                            }

                            // Artists - tappable links
                            if let artists = show.artistsCollection?.items, !artists.isEmpty {
                                ArtistLinksView(artists: artists, navigationPath: $navigationPath)
                            }

                            // Genre badges - website style (centered)
                            if !liveGenres.isEmpty {
                                HStack(spacing: Theme.Spacing.sm) {
                                    ForEach(liveGenres, id: \.self) { genre in
                                        GenreBadge(genre: genre)
                                    }
                                }
                            }

                            // Description
                            if !liveDescription.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    ForEach(liveDescription, id: \.self) { paragraph in
                                        Text(paragraph)
                                            .font(.lightBody(size: Theme.Typography.bodyBase))
                                            .foregroundColor(Theme.foreground.opacity(0.9))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.top, Theme.Spacing.sm)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }

                    // Play/Stop button - pill style
                    PlayButton(isPlaying: radio.isPlaying, isBuffering: radio.isBuffering) {
                        togglePlayback()
                    }
                    .padding(.top, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .background(Theme.background)
            .task {
                await fetchLiveShow()
            }
            .navigationDestination(for: ScheduleDestination.self) { destination in
                switch destination {
                case .showDetail(let show):
                    ShowDetailView(show: show, navigationPath: $navigationPath)
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath)
                }
            }
        }
    }

    private func fetchLiveShow() async {
        do {
            liveShow = try await RefugeAPI.shared.fetchLiveNow()

            if let liveID = liveShow?.id {
                do {
                    // Fetch full show data from nextup to get artistsCollection
                    let nextUpShows = try await RefugeAPI.shared.fetchSchedule()
                    if let fullShow = nextUpShows.first(where: { $0.id == liveID }) {
                        liveShow = fullShow
                    }
                } catch {
                    print("Failed to hydrate live show from nextup:", error)
                }
            }

            // Update Now Playing info with show metadata
            updateNowPlayingMetadata()

            // Fetch the show page description and genres if slug exists
            if let slug = liveShow?.slug,
               let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let showURL = URL(string: "https://refugeworldwide.com/radio/\(encodedSlug)") {
                let (data, _) = try await URLSession.shared.data(from: showURL)
                if let html = String(data: data, encoding: .utf8) {
                    // Parse with SwiftSoup
                    let doc = try SwiftSoup.parse(html)

                    // Extract genres from __NEXT_DATA__ JSON (more reliable than HTML selectors)
                    if let scriptElement = try doc.select("script#__NEXT_DATA__").first(),
                       let jsonString = try? scriptElement.html(),
                       let jsonData = jsonString.data(using: .utf8) {
                        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let props = json["props"] as? [String: Any],
                           let pageProps = props["pageProps"] as? [String: Any],
                           let showData = pageProps["show"] as? [String: Any],
                           let genresCollection = showData["genresCollection"] as? [String: Any],
                           let items = genresCollection["items"] as? [[String: Any]] {
                            liveGenres = items.compactMap { item in
                                (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                            }.filter { !$0.isEmpty }
                        }
                    }

                    // Extract all paragraph texts from main content
                    let paragraphElements = try doc.select("main p")
                    liveDescription = try paragraphElements.array().compactMap { element in
                        let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        // Skip paragraphs that look like dates
                        if text.range(of: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b"#, options: .regularExpression) != nil {
                            return nil
                        }
                        // Skip lines starting with "With "
                        if text.range(of: #"^With\s+.+$"#, options: .regularExpression) != nil {
                            return nil
                        }
                        return text.isEmpty ? nil : text
                    }
                }
            }
        } catch {
            print("Failed to fetch liveNow or description:", error)
        }
    }

    private func togglePlayback() {
        radio.isPlaying ? radio.stop() : radio.play()
    }

    private func updateNowPlayingMetadata() {
        guard let show = liveShow else { return }
        radio.updateNowPlayingInfo(
            title: show.title,
            subtitle: timeString,
            artworkURL: show.coverImage?.url
        )
    }
}

// MARK: - Live Indicator Component

struct LiveIndicator: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(Theme.red)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("LIVE")
                .font(.mediumBody(size: Theme.Typography.caption))
                .tracking(1)
                .foregroundColor(Theme.foreground)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.background.opacity(0.8))
        .clipShape(Capsule())
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Play Button Component

struct PlayButton: View {
    let isPlaying: Bool
    let isBuffering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if isBuffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                }

                Text(isBuffering ? "Loading..." : (isPlaying ? "Stop" : "Listen Live"))
                    .font(.mediumBody(size: Theme.Typography.bodyBase))
            }
            .foregroundColor(Theme.background)
            .frame(minWidth: 160)
            .pillButton(
                backgroundColor: Theme.foreground,
                borderColor: Theme.foreground,
                shadowColor: Theme.Shadow.pillBlack,
                height: 50
            )
        }
        .disabled(isBuffering)
    }
}

// MARK: - Genre Badge Component

struct GenreBadge: View {
    let genre: String

    var body: some View {
        Text(genre)
            .badge(small: true)
    }
}
