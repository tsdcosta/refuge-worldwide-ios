//
//  ScheduleView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI
import Kingfisher

// MARK: - Navigation Destinations

enum ScheduleDestination: Hashable {
    case showDetail(ShowItem)
    case artistDetail(slug: String, name: String)
}

struct ScheduleView: View {
    @Binding var navigationPath: NavigationPath
    @State private var scheduleDays: [ScheduleDay] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    ForEach(scheduleDays) { day in
                        VStack(alignment: .leading, spacing: Theme.Spacing.base) {
                            // Day header - pill style matching website
                            DatePill(date: day.date)
                                .padding(.horizontal, Theme.Spacing.base)

                            // Show cards - no gaps, full width
                            LazyVStack(spacing: 0) {
                                ForEach(day.shows) { show in
                                    NavigationLink(value: ScheduleDestination.showDetail(show)) {
                                        ShowCard(show: show, isLive: show.isLiveNow)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }

                                // Repeats Playlist at the end of the day
                                RepeatsPlaylistCard(lastShowEndTime: day.shows.last?.dateEnd)
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.lg)
                .animation(nil, value: scheduleDays.count)
            }
            .background(Theme.orange)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: ScheduleDestination.self) { destination in
                switch destination {
                case .showDetail(let show):
                    ShowDetailView(show: show, navigationPath: $navigationPath)
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath)
                }
            }
            .task {
                do {
                    let schedule = try await RefugeAPI.shared.fetchSchedule()
                    withAnimation(nil) {
                        scheduleDays = schedule.groupedByDay()
                    }
                } catch {
                    print("Failed to fetch schedule:", error)
                }
            }
        }
    }
}

// MARK: - Show Card Component

struct ShowCard: View {
    let show: ShowItem
    var isLive: Bool = false

    private var timeString: String {
        if let start = show.date {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: start)
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                // Time column - fixed width, light font
                Text(timeString)
                    .font(.lightBody(size: 18))
                    .foregroundColor(isLive ? Color.white : Color.black)
                    .frame(width: 80, alignment: .leading)

                Text(show.title)
                    .font(.lightBody(size: 18))
                    .foregroundColor(isLive ? Color.white : Color.black)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if isLive {
                    LiveDot()
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(isLive ? Color.black : Color.clear)

            // Separator
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.08))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Repeats Playlist Card

struct RepeatsPlaylistCard: View {
    let lastShowEndTime: Date?

    private var timeString: String {
        guard let endTime = lastShowEndTime else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: endTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Text(timeString)
                    .font(.lightBody(size: 18))
                    .foregroundColor(Color.black)
                    .frame(width: 80, alignment: .leading)

                Text("Repeats Playlist")
                    .font(.lightBody(size: 18))
                    .foregroundColor(Color.black)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.lg)
            .background(Color.clear)

            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.08))
        }
    }
}

// MARK: - Live Dot Component

struct LiveDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            // Drive opacity from time only, no state or implicit layout animation
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.2)) / 1.2
            let opacity = 0.3 + 0.7 * abs(sin(.pi * phase))

            Circle()
                .fill(Theme.red)
                .frame(width: 6, height: 6)
                .opacity(opacity)
                .fixedSize() // prevents baseline/layout jitter inside text stacks
        }
    }
}

// MARK: - Date Pill Component

struct DatePill: View {
    let date: Date

    var body: some View {
        Text(shortDateFormatter.string(from: date))
            .font(.serifHeading(size: Theme.Typography.headingSmall))
            .foregroundColor(.black)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Theme.orange)
                    // Black shadow offset downward creates thicker bottom effect
                    .shadow(color: .black, radius: 0, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 1.5)
            )
    }
}

// MARK: - Date Formatter

private let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE d MMM"  // "Fri 20 Dec"
    return formatter
}()

// MARK: - Show Detail View

struct ShowDetailView: View {
    let show: ShowItem
    @Binding var navigationPath: NavigationPath
    @State private var description: [String] = []
    @State private var genres: [String] = []
    @State private var relatedShows: [ShowDetail.RelatedShow] = []
    @State private var artists: [ShowItem.Artist] = []

    // Format date like "20 Dec 2025"
    private var formattedDate: String? {
        guard let date = show.date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
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
                            .padding(.top, Theme.Spacing.lg)
                    }

                    // Title - serif style
                    Text(show.title.replacingOccurrences(of: #" - .*$"#, with: "", options: .regularExpression))
                        .font(.serifHeading(size: Theme.Typography.headingBase))
                        .foregroundColor(Theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, formattedDate == nil ? Theme.Spacing.lg : Theme.Spacing.sm)

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
                                NavigationLink(value: ScheduleDestination.showDetail(ShowItem(from: relatedShow))) {
                                    RelatedShowCard(show: relatedShow, navigationPath: $navigationPath)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Play button moved out of the card so it is tappable independently
                                if let mixcloudLink = relatedShow.mixcloudLink, !mixcloudLink.isEmpty {
                                    ShowPlayButton(
                                        mixcloudLink: mixcloudLink,
                                        title: relatedShow.title,
                                        artworkURL: relatedShow.coverImageURL
                                    )
                                    .frame(width: 44, height: 44)
                                    .padding(.trailing, Theme.Spacing.lg)
                                } else {
                                    Spacer()
                                        .frame(width: Theme.Spacing.lg)
                                }
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
         .task {
             // Initialize from passed show data if available
             if let showArtists = show.artistsCollection?.items, artists.isEmpty {
                 artists = showArtists
             }
             await fetchShowDetail()
         }
     }

     func fetchShowDetail() async {
        guard let slug = show.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

        do {
            // Use the API to fetch show details
            let showDetail = try await RefugeAPI.shared.fetchShowDetail(slug: slug)

            // Map genres safely
            if let g = showDetail.genres {
                genres = g.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else {
                genres = []
            }

            // Map description: prefer pre-split paragraphs, otherwise split text
            if let paragraphs = showDetail.descriptionParagraphs, !paragraphs.isEmpty {
                description = paragraphs
            } else if let text = showDetail.description {
                description = splitIntoParagraphs(text)
            } else {
                description = []
            }

            // Map related shows
            relatedShows = showDetail.relatedShows ?? []

            // Map artists from fetched detail
            if let fetchedArtists = showDetail.artistsCollection?.items {
                artists = fetchedArtists.map { ShowItem.Artist(name: $0.name, slug: $0.slug) }
            }
        } catch {
            print("Failed to fetch show details:", error)
        }
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        let parts = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts
    }
}

// MARK: - Artist Links View

struct ArtistLinksView: View {
    let artists: [ShowItem.Artist]
    var navigationPath: Binding<NavigationPath>? = nil

    var body: some View {
        // Format: "With artist1, artist2, and artist3" or "With artist" or "With artist1 and artist2"
        HStack(spacing: 0) {
            Text("With  ")
                .font(.lightBody(size: Theme.Typography.bodySmall))
                .foregroundColor(Theme.secondaryText)

            ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                // Artist link
                if let _ = navigationPath {
                    NavigationLink(value: ScheduleDestination.artistDetail(slug: artist.slug, name: artist.name)) {
                        Text(artist.name)
                            .font(.lightBody(size: Theme.Typography.bodySmall))
                            .foregroundColor(Theme.foreground)
                            .underline()
                    }
                } else {
                    Text(artist.name)
                        .font(.lightBody(size: Theme.Typography.bodySmall))
                        .foregroundColor(Theme.foreground)
                        .underline()
                }

                // Separator: ", " for all but last two, " and " before last
                if artists.count > 1 {
                    if index < artists.count - 2 {
                        Text(", ")
                            .font(.lightBody(size: Theme.Typography.bodySmall))
                            .foregroundColor(Theme.secondaryText)
                    } else if index == artists.count - 2 {
                        Text(" and  ")
                            .font(.lightBody(size: Theme.Typography.bodySmall))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - Artist Detail View

struct ArtistDetailView: View {
    let artistSlug: String
    let artistName: String
    @Binding var navigationPath: NavigationPath
    @State private var artist: ArtistResponse?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                        .padding(.top, 100)
                } else if let artist = artist {
                    // Artist photo - square
                    if let photoURL = artist.photo?.url {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                KFImage(photoURL)
                                    .resizable()
                                    .scaledToFill()
                            )
                            .clipped()
                    }

                    VStack(spacing: Theme.Spacing.base) {
                        // Name - serif style
                        Text(artist.name)
                            .font(.serifHeading(size: Theme.Typography.headingBase))
                            .foregroundColor(Theme.foreground)
                            .multilineTextAlignment(.center)
                            .padding(.top, Theme.Spacing.lg)

                        // Description
                        if let description = artist.description, !description.isEmpty {
                            Text(description)
                                .font(.lightBody(size: Theme.Typography.bodyBase))
                                .foregroundColor(Theme.foreground.opacity(0.9))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Theme.Spacing.sm)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)

                    // Past shows - full width, outside padded content
                    if let shows = artist.shows, !shows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Past Shows")
                                .font(.serifHeading(size: Theme.Typography.headingSmall))
                                .foregroundColor(Theme.foreground)
                                .padding(.top, Theme.Spacing.lg)
                                .padding(.bottom, Theme.Spacing.base)
                                .padding(.horizontal, Theme.Spacing.lg)

                            ForEach(Array(shows.enumerated()), id: \.element.id) { index, show in
                                HStack(spacing: Theme.Spacing.md) {
                                    NavigationLink(value: ScheduleDestination.showDetail(ShowItem(from: show))) {
                                        ArtistShowCard(show: show)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    // Play button moved out so it can be tapped separately from navigation
                                    if let mixcloudLink = show.mixcloudLink, !mixcloudLink.isEmpty {
                                        ShowPlayButton(
                                            mixcloudLink: mixcloudLink,
                                            title: show.title,
                                            artworkURL: show.coverImageURL
                                        )
                                        .frame(width: 44, height: 44)
                                        .padding(.trailing, Theme.Spacing.lg)
                                    } else {
                                        Spacer()
                                            .frame(width: Theme.Spacing.lg)
                                    }
                                }

                                 // Separator between items (not after last)
                                 if index < shows.count - 1 {
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
                 } else {
                     Text("Failed to load artist")
                         .font(.lightBody(size: Theme.Typography.bodyBase))
                         .foregroundColor(Theme.secondaryText)
                         .padding(.top, 100)
                 }
             }
             .padding(.bottom, Theme.Spacing.xl)
         }
         .background(Theme.background)
         .task {
             do {
                 artist = try await RefugeAPI.shared.fetchArtist(slug: artistSlug)
             } catch {
                 print("Failed to fetch artist:", error)
             }
             isLoading = false
         }
    }
}

// MARK: - Artist Show Card

struct ArtistShowCard: View {
    let show: ArtistResponse.ArtistShow
    private let rowHeight: CGFloat = 80

    private var formattedDate: String? {
        guard let dateStr = show.date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Cover image - indented to match section title
            if let url = show.coverImageURL {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: rowHeight, height: rowHeight)
                    .clipped()
            } else {
                Theme.cardBackground
                    .frame(width: rowHeight, height: rowHeight)
            }

            // Text content - left aligned
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(show.title)
                    .font(.mediumBody(size: Theme.Typography.bodySmall))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let date = formattedDate {
                    Text(date)
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(Theme.secondaryText)
                }

                // Genre badges
                if let genres = show.genres, !genres.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(genres.prefix(2), id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 9, weight: .medium))
                                .textCase(.uppercase)
                                .tracking(0.3)
                                .foregroundColor(Theme.foreground.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.foreground.opacity(0.3), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Spacer preserved; actual play button is rendered outside the card so it can be tapped
            Spacer()
                .frame(width: Theme.Spacing.lg)
        }
        .padding(.leading, Theme.Spacing.lg)
        .frame(minHeight: rowHeight)
        .background(Theme.background)
    }
}

// MARK: - Related Show Card

struct RelatedShowCard: View {
    let show: ShowDetail.RelatedShow
    @Binding var navigationPath: NavigationPath
    private let rowHeight: CGFloat = 80

    private var formattedDate: String? {
        guard let dateStr = show.date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateStr) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Cover image - indented to match section title
            if let url = show.coverImageURL {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: rowHeight, height: rowHeight)
                    .clipped()
            } else {
                Theme.cardBackground
                    .frame(width: rowHeight, height: rowHeight)
            }

            // Text content - left aligned
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(show.title)
                    .font(.mediumBody(size: Theme.Typography.bodySmall))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let date = formattedDate {
                    Text(date)
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(Theme.secondaryText)
                }

                // Artist links
                if let artists = show.artistsCollection?.items, !artists.isEmpty {
                    RelatedShowArtistLinks(artists: artists, navigationPath: $navigationPath)
                }

                // Genre badges
                if let genres = show.genres, !genres.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(genres.prefix(2), id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 9, weight: .medium))
                                .textCase(.uppercase)
                                .tracking(0.3)
                                .foregroundColor(Theme.foreground.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.foreground.opacity(0.3), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Theme.Spacing.lg)
        .frame(minHeight: rowHeight)
        .background(Theme.background)
    }
}

// MARK: - Related Show Artist Links

struct RelatedShowArtistLinks: View {
    let artists: [ShowDetail.Artist]
    @Binding var navigationPath: NavigationPath

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(artists.enumerated()), id: \.element.slug) { index, artist in
                NavigationLink(value: ScheduleDestination.artistDetail(slug: artist.slug, name: artist.name)) {
                    Text(artist.name)
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(Theme.foreground)
                        .underline()
                }

                if artists.count > 1 {
                    if index < artists.count - 2 {
                        Text(", ")
                            .font(.lightBody(size: Theme.Typography.caption))
                            .foregroundColor(Theme.secondaryText)
                    } else if index == artists.count - 2 {
                        Text(" & ")
                            .font(.lightBody(size: Theme.Typography.caption))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            }
        }
    }
}

// MARK: - Show Play Button

struct ShowPlayButton: View {
    let mixcloudLink: String
    let title: String
    let artworkURL: URL?

    @ObservedObject private var radio = RadioPlayer.shared

    private var streamURL: URL? {
        URL(string: mixcloudLink)
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
        Button {
            guard let url = streamURL else { return }
            if isThisPlaying {
                radio.stop()
            } else {
                radio.playURL(url, title: title, artworkURL: artworkURL)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.foreground)
                    .frame(width: 36, height: 36)

                if isThisBuffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.background))
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isThisPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.background)
                        .offset(x: isThisPlaying ? 0 : 1)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
