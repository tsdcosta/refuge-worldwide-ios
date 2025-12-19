//
//  ScheduleView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI
import SwiftSoup
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
                            // Day header - serif style
                            Text(day.date, formatter: fullDateFormatter)
                                .font(.serifHeading(size: Theme.Typography.headingSmall))
                                .foregroundColor(Theme.foreground)
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
            }
            .background(Theme.background)
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
                    scheduleDays = schedule.groupedByDay()
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
        VStack(spacing: 0) {
            // Cover image - rectangle on top, full width
            KFImage(show.coverImage?.url)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()

            // Bottom section with title and time - centered
            VStack(spacing: Theme.Spacing.xs) {
                // Title with optional live dot
                HStack(spacing: Theme.Spacing.xs) {
                    Text(show.title)
                        .font(.mediumBody(size: Theme.Typography.bodySmall))
                        .foregroundColor(isLive ? Theme.background : Theme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if isLive {
                        LiveDot()
                    }
                }

                // Time - smaller than title
                if !timeString.isEmpty {
                    Text(timeString)
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(isLive ? Theme.background.opacity(0.7) : Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.base)
            .background(isLive ? Theme.foreground : Theme.cardBackground)
        }
        .contentShape(Rectangle())
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
            // Orange rectangle on top (no image)
            Theme.orange
                .frame(height: 180)
                .frame(maxWidth: .infinity)

            // Bottom section with title and time - centered
            VStack(spacing: Theme.Spacing.xs) {
                Text("Repeats Playlist")
                    .font(.mediumBody(size: Theme.Typography.bodySmall))
                    .foregroundColor(Theme.foreground)

                if !timeString.isEmpty {
                    Text(timeString)
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.base)
            .background(Theme.cardBackground)
        }
    }
}

// MARK: - Genre Pill Component (legacy - keeping for compatibility)

struct GenrePill: View {
    let genre: String

    var body: some View {
        Text(genre)
            .badge(small: true)
    }
}

// MARK: - Date Formatter

private let fullDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return formatter
}()

// MARK: - Show Detail View

struct ShowDetailView: View {
    let show: ShowItem
    @Binding var navigationPath: NavigationPath
    @State private var description: [String] = []
    @State private var genres: [String] = []

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
                    if let artists = show.artistsCollection?.items, !artists.isEmpty {
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
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.background)
        .task {
            await fetchShowDetail()
        }
    }

    func fetchShowDetail() async {
        guard let slug = show.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://refugeworldwide.com/radio/\(slug)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return }

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
                    genres = items.compactMap { item in
                        (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                }
            }

            // Extract description paragraphs
            let paragraphElements = try doc.select("main p")
            description = try paragraphElements.array().compactMap { element in
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
        } catch {
            print("Failed to fetch show details:", error)
        }
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

                        // Past shows
                        if let shows = artist.shows, !shows.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.base) {
                                Text("Past Shows")
                                    .font(.serifHeading(size: Theme.Typography.headingSmall))
                                    .foregroundColor(Theme.foreground)
                                    .padding(.top, Theme.Spacing.lg)

                                ForEach(shows) { show in
                                    ArtistShowCard(show: show)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
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
        .navigationTitle(artistName)
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
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Cover image
            if let url = show.coverImageURL {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipped()
                    .cornerRadius(Theme.Radius.small)
            } else {
                Theme.cardBackground
                    .frame(width: 64, height: 64)
                    .cornerRadius(Theme.Radius.small)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(show.title)
                    .font(.mediumBody(size: Theme.Typography.bodySmall))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

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
                                        .stroke(Theme.foreground.opacity(0.25), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.Radius.medium)
    }
}
