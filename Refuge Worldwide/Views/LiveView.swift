//
//  LiveView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI

struct LiveView: View {
    var onShowSelected: ((ShowItem) -> Void)?

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

                        // Live indicator - only show when live stream is active
                        if (radio.isPlaying || radio.isBuffering) && radio.isLiveStream {
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

                            // Genre badges - website style (centered)
                            if !liveGenres.isEmpty {
                                HStack(spacing: Theme.Spacing.sm) {
                                    ForEach(liveGenres, id: \.self) { genre in
                                        GenreBadge(genre: genre)
                                    }
                                }
                            }
                            
                            // Artists - tappable links
                            if let artists = show.artistsCollection?.items, !artists.isEmpty {
                                ArtistLinksView(artists: artists, navigationPath: $navigationPath)
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

                    // Play/Stop button - pill style (only reflects live stream state)
                    PlayButton(
                        isPlaying: radio.isPlaying && radio.isLiveStream,
                        isBuffering: radio.isBuffering && radio.isLiveStream
                    ) {
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
                    ShowDetailContent(show: show, navigationPath: $navigationPath, onShowSelected: onShowSelected)
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath, onShowSelected: onShowSelected)
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
            if let slug = liveShow?.slug {
                do {
                    let detail = try await RefugeAPI.shared.fetchShowDetail(slug: slug)

                    if let g = detail.genres {
                        liveGenres = g.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }

                    if let paragraphs = detail.descriptionParagraphs, !paragraphs.isEmpty {
                        liveDescription = paragraphs
                    } else if let text = detail.description {
                        liveDescription = splitIntoParagraphs(text)
                    } else {
                        liveDescription = []
                    }
                } catch {
                    print("Failed to fetch show detail via API, original HTML fallback could be used:", error)
                }
            }
        } catch {
            print("Failed to fetch liveNow or description:", error)
        }
    }

    private func togglePlayback() {
        // Only stop if the live stream specifically is playing
        // If SoundCloud is playing, calling play() will stop it and start live
        if radio.isPlaying && radio.isLiveStream {
            radio.stop()
        } else {
            radio.play()
        }
    }

    private func updateNowPlayingMetadata() {
        guard let show = liveShow else { return }
        radio.updateNowPlayingInfo(
            title: show.title,
            subtitle: timeString,
            artworkURL: show.coverImage?.url
        )
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        let parts = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts
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
