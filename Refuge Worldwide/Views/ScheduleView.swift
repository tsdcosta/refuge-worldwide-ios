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
    var onShowSelected: ((ShowItem) -> Void)?
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
                                    Button {
                                        onShowSelected?(show)
                                    } label: {
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
                    ShowDetailContent(show: show, navigationPath: $navigationPath, onShowSelected: onShowSelected)
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath, onShowSelected: onShowSelected)
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
    var onShowSelected: ((ShowItem) -> Void)?
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
                                    Button {
                                        onShowSelected?(ShowItem(from: show))
                                    } label: {
                                        ArtistShowCard(show: show)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(maxWidth: .infinity, alignment: .leading)

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
