//
//  ShowsView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/20/25.
//

import SwiftUI
import Kingfisher

// MARK: - Shows View (tab for past/future shows with playback)

struct ShowsView: View {
    let show: ShowItem?
    @Binding var navigationPath: NavigationPath
    var onShowSelected: ((ShowItem) -> Void)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let show = show {
                    ShowDetailContent(
                        show: show,
                        navigationPath: $navigationPath,
                        onShowSelected: onShowSelected
                    )
                } else {
                    EmptyShowsView()
                }
            }
            .navigationDestination(for: ScheduleDestination.self) { destination in
                switch destination {
                case .showDetail(let show):
                    ShowDetailContent(
                        show: show,
                        navigationPath: $navigationPath,
                        onShowSelected: onShowSelected
                    )
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath)
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyShowsView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "play.circle")
                .font(.system(size: 64))
                .foregroundColor(Theme.secondaryText)

            Text("No Show Selected")
                .font(.serifHeading(size: Theme.Typography.headingSmall))
                .foregroundColor(Theme.foreground)

            Text("Select a show from the Schedule to view details and listen to past recordings.")
                .font(.lightBody(size: Theme.Typography.bodySmall))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

// MARK: - Show Detail Content

struct ShowDetailContent: View {
    let show: ShowItem
    @Binding var navigationPath: NavigationPath
    var onShowSelected: ((ShowItem) -> Void)?

    @State private var description: [String] = []
    @State private var genres: [String] = []
    @State private var relatedShows: [ShowDetail.RelatedShow] = []
    @State private var artists: [ShowItem.Artist] = []
    @State private var mixcloudLink: String?
    @State private var lastLoadedSlug: String?

    @ObservedObject private var radio = RadioPlayer.shared

    // Format date like "20 Dec 2025"
    private var formattedDate: String? {
        guard let date = show.date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private var streamURL: URL? {
        guard let link = mixcloudLink else { return nil }
        return URL(string: link)
    }

    private var isThisPlaying: Bool {
        guard let url = streamURL else { return false }
        return radio.isPlayingURL(url)
    }

    private var isThisBuffering: Bool {
        guard let url = streamURL else { return false }
        return radio.isBuffering && radio.currentPlayingURL == url
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Cover image - full width, square
                if let url = show.coverImage?.url {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipped()
                }

                VStack(spacing: Theme.Spacing.base) {
                    // Date - like "20 Dec 2025"
                    if let date = formattedDate {
                        Text(date)
                            .font(.lightBody(size: Theme.Typography.bodySmall))
                            .foregroundColor(Theme.secondaryText)
                            .padding(.top, mixcloudLink != nil ? Theme.Spacing.sm : Theme.Spacing.lg)
                    }

                    // Title - serif style
                    Text(show.title.replacingOccurrences(of: #" - .*$"#, with: "", options: .regularExpression))
                        .font(.serifHeading(size: Theme.Typography.headingBase))
                        .foregroundColor(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, formattedDate == nil && mixcloudLink == nil ? Theme.Spacing.lg : Theme.Spacing.sm)

                    // Genre badges (centered)
                    if !genres.isEmpty {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(genres, id: \.self) { genre in
                                GenreBadge(genre: genre)
                            }
                        }
                    }

                    // Artists - tappable links
                    if !artists.isEmpty {
                        ArtistLinksView(artists: artists, navigationPath: $navigationPath)
                    }
                    
                    // Play button - prominent, centered
                    if let link = mixcloudLink, !link.isEmpty {
                        Button {
                            guard let url = streamURL else { return }
                            if isThisPlaying {
                                radio.stop()
                            } else {
                                radio.playURL(url, title: show.title, artworkURL: show.coverImage?.url)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.foreground)
                                    .frame(width: 64, height: 64)

                                if isThisBuffering {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                                        .scaleEffect(1.0)
                                } else {
                                    Image(systemName: isThisPlaying ? "stop.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(Theme.background)
                                        .offset(x: isThisPlaying ? 0 : 2)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, Theme.Spacing.lg)
                    }

                    // Description
                    if !description.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(description, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.lightBody(size: Theme.Typography.bodyBase))
                                    .foregroundColor(Theme.foreground.opacity(0.9))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.md)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)

                // Related shows - full width, outside padded content
                if !relatedShows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Related Shows")
                            .font(.serifHeading(size: Theme.Typography.headingSmall))
                            .foregroundColor(Theme.foreground)
                            .padding(.top, Theme.Spacing.lg)
                            .padding(.bottom, Theme.Spacing.base)
                            .padding(.horizontal, Theme.Spacing.lg)

                        ForEach(Array(relatedShows.enumerated()), id: \.element.id) { index, relatedShow in
                            HStack(spacing: Theme.Spacing.md) {
                                // Tappable card - calls onShowSelected to switch show at root level
                                Button {
                                    onShowSelected?(ShowItem(from: relatedShow))
                                } label: {
                                    RelatedShowCard(show: relatedShow, navigationPath: $navigationPath)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)

                            }

                            // Separator between items (not after last)
                            if index < relatedShows.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 1)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.background)
        .task(id: show.slug) {
            await loadShowIfNeeded()
        }
    }

    private func loadShowIfNeeded() async {
        // Only reload if the show changed
        guard lastLoadedSlug != show.slug else { return }

        // Reset state for new show
        description = []
        genres = []
        relatedShows = []
        mixcloudLink = nil

        // Initialize from passed show data if available
        if let showArtists = show.artistsCollection?.items {
            artists = showArtists
        } else {
            artists = []
        }

        await fetchShowDetail()
        lastLoadedSlug = show.slug
    }

    private func fetchShowDetail() async {
        guard let slug = show.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

        do {
            let showDetail = try await RefugeAPI.shared.fetchShowDetail(slug: slug)

            mixcloudLink = showDetail.mixcloudLink

            if let g = showDetail.genres {
                genres = g.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else {
                genres = []
            }

            if let paragraphs = showDetail.descriptionParagraphs, !paragraphs.isEmpty {
                description = paragraphs
            } else if let text = showDetail.description {
                description = splitIntoParagraphs(text)
            } else {
                description = []
            }

            relatedShows = showDetail.relatedShows ?? []

            if let fetchedArtists = showDetail.artistsCollection?.items {
                artists = fetchedArtists.map { ShowItem.Artist(name: $0.name, slug: $0.slug) }
            }
        } catch {
            print("Failed to fetch show details:", error)
        }
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
