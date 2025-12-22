//
//  ArtistView.swift
//  Refuge Worldwide
//
//  Created by Tiago on 12/21/25.
//

import SwiftUI
import Kingfisher

// MARK: - Artist Type Tab

enum ArtistType: String, CaseIterable {
    case residents = "RESIDENTS"
    case guests = "GUESTS"

    var isResident: Bool {
        self == .residents
    }
}

// MARK: - Letter Section (for grouped artist lists)

struct LetterSection: Identifiable, Equatable {
    let letter: String
    let artists: [ArtistListItem]

    var id: String { letter }

    static func == (lhs: LetterSection, rhs: LetterSection) -> Bool {
        lhs.letter == rhs.letter && lhs.artists.map(\.id) == rhs.artists.map(\.id)
    }
}

// MARK: - Artists List View (tab view)

struct ArtistsView: View {
    @Binding var navigationPath: NavigationPath
    var onShowSelected: ((ShowItem) -> Void)?
    var onArtistSelected: ((String, String) -> Void)?

    @State private var selectedType: ArtistType = .residents
    @State private var residents: [ArtistListItem] = []
    @State private var guests: [ArtistListItem] = []
    @State private var allResidentSlugs: Set<String> = []
    @State private var searchText = ""
    @State private var searchResults: [ArtistListItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var isLoadingResidents = true
    @State private var isLoadingGuests = true
    @State private var hasMoreResidents = true
    @State private var hasMoreGuests = true
    @State private var residentsSkip = 0
    @State private var guestsSkip = 0
    @State private var groupedArtists: [LetterSection] = []
    @State private var otherResidents: [ArtistListItem] = []  // Accented + special chars, added at end
    @State private var otherGuests: [ArtistListItem] = []
    private let pageSize = 50
    private let asciiLetters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    private var isInSearchMode: Bool {
        !searchText.isEmpty
    }

    private var currentArtists: [ArtistListItem] {
        selectedType == .residents ? residents : guests
    }

    private var isLoading: Bool {
        selectedType == .residents ? isLoadingResidents : isLoadingGuests
    }

    private var hasMore: Bool {
        guard !isInSearchMode else { return false }
        return selectedType == .residents ? hasMoreResidents : hasMoreGuests
    }

    private var displayedArtists: [ArtistListItem] {
        isInSearchMode ? searchResults : currentArtists
    }

    // Compute grouped artists from the given list - optimized to avoid redundant work
    private func computeGroupedArtists(from artists: [ArtistListItem]) -> [LetterSection] {
        guard !artists.isEmpty else { return [] }

        // Group first, then sort within each group only if needed
        var grouped: [String: [ArtistListItem]] = [:]
        grouped.reserveCapacity(27) // A-Z + #

        for artist in artists {
            let first = artist.name.prefix(1).uppercased()
            let key: String
            if first.isEmpty {
                key = "#"
            } else if first.unicodeScalars.first.map({ CharacterSet.letters.contains($0) }) == true {
                key = first
            } else {
                key = "#"
            }
            grouped[key, default: []].append(artist)
        }

        // Sort keys: A-Z first, then #
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }

        // Sort artists within each section and create LetterSection
        return sortedKeys.map { key in
            let sectionArtists = grouped[key]!.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return LetterSection(letter: key, artists: sectionArtists)
        }
    }

    private func updateGroupedArtists() {
        groupedArtists = computeGroupedArtists(from: displayedArtists)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Search bar - horizontal line style
                VStack(spacing: 0) {
                    HStack {
                        TextField("", text: $searchText, prompt: Text("Search artists").foregroundColor(Color.black.opacity(0.5)))
                            .font(.lightBody(size: Theme.Typography.bodyBase))
                            .foregroundColor(.black)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.black.opacity(0.5)))
                                .scaleEffect(0.8)
                        } else if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color.black.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.base)
                    .padding(.bottom, Theme.Spacing.sm)

                    // Black horizontal line
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.base)
                .padding(.bottom, Theme.Spacing.md)

                // RESIDENTS / GUESTS tabs - hidden during search
                if !isInSearchMode {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(ArtistType.allCases, id: \.self) { type in
                            Button {
                                selectedType = type
                            } label: {
                                ArtistTypePill(title: type.rawValue, isSelected: selectedType == type)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.base)
                    .padding(.bottom, Theme.Spacing.md)
                }

                if !isInSearchMode && isLoading && currentArtists.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                    Spacer()
                } else if isInSearchMode && isSearching {
                    // Show loading while search is in progress
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.black))
                    Spacer()
                } else if displayedArtists.isEmpty {
                    Spacer()
                    Text(isInSearchMode ? "No results for \"\(searchText)\"" : "No artists found")
                        .font(.lightBody(size: Theme.Typography.bodyBase))
                        .foregroundColor(.black)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedArtists) { section in
                                Section {
                                    ForEach(Array(section.artists.enumerated()), id: \.element.id) { index, artist in
                                        Button {
                                            navigationPath.append(ScheduleDestination.artistDetail(slug: artist.slug, name: artist.name))
                                        } label: {
                                            ArtistRow(artist: artist, showResidentBadge: isInSearchMode && artist.isResident)
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        if index < section.artists.count - 1 {
                                            Rectangle()
                                                .fill(Color.black.opacity(0.08))
                                                .frame(height: 1)
                                                .padding(.horizontal, Theme.Spacing.lg)
                                        }
                                    }
                                } header: {
                                    LetterPill(letter: section.letter)
                                        .padding(.horizontal, Theme.Spacing.base)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .background(Theme.purple)
                                }
                            }

                            // Load more indicator - only for paginated list, not search
                            if hasMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color.black.opacity(0.5)))
                                    Spacer()
                                }
                                .padding(.vertical, Theme.Spacing.lg)
                                .onAppear {
                                    Task {
                                        await loadMoreArtists()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(Theme.purple)
            .navigationDestination(for: ScheduleDestination.self) { destination in
                switch destination {
                case .showDetail(let show):
                    ShowDetailContent(show: show, navigationPath: $navigationPath, isSearchMode: .constant(false), searchText: .constant(""), searchResults: .constant([]), onShowSelected: onShowSelected)
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath, onShowSelected: onShowSelected)
                }
            }
            .task {
                await loadInitialArtists()
            }
            .onChange(of: searchText) { _, newValue in
                // Cancel any existing search
                searchTask?.cancel()

                if newValue.isEmpty {
                    searchResults = []
                    isSearching = false
                    updateGroupedArtists()
                    return
                }

                // Show loading immediately when typing
                isSearching = true

                // Debounce: wait 300ms before searching
                searchTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    } catch {
                        return // Task was cancelled
                    }

                    guard !Task.isCancelled else { return }

                    await performSearch(query: newValue)
                }
            }
            .onChange(of: residents) { _, _ in
                if selectedType == .residents && !isInSearchMode {
                    updateGroupedArtists()
                }
            }
            .onChange(of: guests) { _, _ in
                if selectedType == .guests && !isInSearchMode {
                    updateGroupedArtists()
                }
            }
            .onChange(of: searchResults) { _, _ in
                if isInSearchMode {
                    updateGroupedArtists()
                }
            }
            .onChange(of: selectedType) { _, _ in
                if !isInSearchMode {
                    updateGroupedArtists()
                }
            }
        }
    }

    private func performSearch(query: String) async {
        isSearching = true
        do {
            let results = try await RefugeAPI.shared.searchArtists(query: query)
            // Only update if we haven't been cancelled and query still matches
            if !Task.isCancelled && searchText == query {
                // Cross-reference with all resident slugs to identify them
                searchResults = results.map { artist in
                    if allResidentSlugs.contains(artist.slug) {
                        return ArtistListItem(
                            id: artist.id,
                            name: artist.name,
                            slug: artist.slug,
                            isResident: true,
                            photoURL: artist.photoURL
                        )
                    }
                    return artist
                }
            }
        } catch {
            if !Task.isCancelled {
                print("Search failed:", error)
                searchResults = []
            }
        }
        if !Task.isCancelled {
            isSearching = false
        }
    }

    // Check if artist name starts with basic ASCII letter (A-Z, no accents)
    private func startsWithAsciiLetter(_ artist: ArtistListItem) -> Bool {
        guard let firstScalar = artist.name.unicodeScalars.first else { return false }
        return asciiLetters.contains(firstScalar)
    }

    // Partition artists into (ASCII A-Z, others)
    private func partitionArtists(_ artists: [ArtistListItem]) -> (ascii: [ArtistListItem], other: [ArtistListItem]) {
        var ascii: [ArtistListItem] = []
        var other: [ArtistListItem] = []
        for artist in artists {
            if startsWithAsciiLetter(artist) {
                ascii.append(artist)
            } else {
                other.append(artist)
            }
        }
        return (ascii, other)
    }

    private func loadInitialArtists() async {
        // Load residents if empty
        if residents.isEmpty {
            isLoadingResidents = true
            do {
                let fetched = try await RefugeAPI.shared.fetchArtists(isResident: true, limit: pageSize, skip: 0)
                let (ascii, other) = partitionArtists(fetched)
                residents = ascii
                residentsSkip = fetched.count
                hasMoreResidents = fetched.count == pageSize
                // If no more pages, append "other" artists now; otherwise save for later
                if hasMoreResidents {
                    otherResidents.append(contentsOf: other)
                } else {
                    residents.append(contentsOf: other)
                }
            } catch {
                print("Failed to fetch residents:", error)
            }
            isLoadingResidents = false
        }

        // Load guests if empty
        if guests.isEmpty {
            isLoadingGuests = true
            do {
                let fetched = try await RefugeAPI.shared.fetchArtists(isResident: false, limit: pageSize, skip: 0)
                let (ascii, other) = partitionArtists(fetched)
                guests = ascii
                guestsSkip = fetched.count
                hasMoreGuests = fetched.count == pageSize
                // If no more pages, append "other" artists now; otherwise save for later
                if hasMoreGuests {
                    otherGuests.append(contentsOf: other)
                } else {
                    guests.append(contentsOf: other)
                }
            } catch {
                print("Failed to fetch guests:", error)
            }
            isLoadingGuests = false
        }

        // Load all resident slugs for search cross-referencing (in background)
        if allResidentSlugs.isEmpty {
            Task {
                await loadAllResidentSlugs()
            }
        }
    }

    private func loadAllResidentSlugs() async {
        var slugs: Set<String> = []
        var skip = 0
        let batchSize = 100

        while true {
            do {
                let batch = try await RefugeAPI.shared.fetchArtists(isResident: true, limit: batchSize, skip: skip)
                if batch.isEmpty { break }
                slugs.formUnion(batch.map { $0.slug })
                skip += batch.count
                if batch.count < batchSize { break }
            } catch {
                print("Failed to load resident slugs:", error)
                break
            }
        }

        allResidentSlugs = slugs
    }

    private func loadMoreArtists() async {
        if selectedType == .residents && hasMoreResidents {
            do {
                let more = try await RefugeAPI.shared.fetchArtists(isResident: true, limit: pageSize, skip: residentsSkip)
                let (ascii, other) = partitionArtists(more)
                residents.append(contentsOf: ascii)
                otherResidents.append(contentsOf: other)
                residentsSkip += more.count
                hasMoreResidents = more.count == pageSize
                // When pagination ends, append the "other" artists (accented + special chars)
                if !hasMoreResidents && !otherResidents.isEmpty {
                    residents.append(contentsOf: otherResidents)
                    otherResidents = []
                }
            } catch {
                print("Failed to load more residents:", error)
            }
        } else if selectedType == .guests && hasMoreGuests {
            do {
                let more = try await RefugeAPI.shared.fetchArtists(isResident: false, limit: pageSize, skip: guestsSkip)
                let (ascii, other) = partitionArtists(more)
                guests.append(contentsOf: ascii)
                otherGuests.append(contentsOf: other)
                guestsSkip += more.count
                hasMoreGuests = more.count == pageSize
                // When pagination ends, append the "other" artists (accented + special chars)
                if !hasMoreGuests && !otherGuests.isEmpty {
                    guests.append(contentsOf: otherGuests)
                    otherGuests = []
                }
            } catch {
                print("Failed to load more guests:", error)
            }
        }
    }
}

// MARK: - Artist Type Pill

struct ArtistTypePill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isSelected ? .white : .black)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black : Theme.purple)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white : Color.black, lineWidth: 1.5)
            )
    }
}

// MARK: - Letter Pill (like DatePill but white/black)

struct LetterPill: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(.serifHeading(size: Theme.Typography.headingSmall))
            .foregroundColor(.black)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Color.white)
                    // Black shadow offset downward creates thicker bottom effect
                    .shadow(color: .black, radius: 0, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 1.5)
            )
    }
}

// MARK: - Artist Row

struct ArtistRow: View {
    let artist: ArtistListItem
    var showResidentBadge: Bool = false
    private let imageSize: CGFloat = 60

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Artist photo - circular with optimized loading
            if let photoURL = artist.photoURL {
                KFImage(photoURL)
                    .placeholder {
                        Circle()
                            .fill(Color.black.opacity(0.1))
                    }
                    .loadDiskFileSynchronously()
                    .fade(duration: 0.15)
                    .cancelOnDisappear(true)
                    .downsampling(size: CGSize(width: imageSize * 2, height: imageSize * 2))
                    .cacheOriginalImage()
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageSize, height: imageSize)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: imageSize, height: imageSize)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(artist.name)
                    .font(.lightBody(size: Theme.Typography.bodyBase))
                    .foregroundColor(.black)

                if showResidentBadge {
                    Text("Resident")
                        .font(.lightBody(size: Theme.Typography.caption))
                        .foregroundColor(Color.black.opacity(0.6))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.black.opacity(0.5))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.purple)
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
                                    .loadDiskFileSynchronously()
                                    .cacheOriginalImage()
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
                    .placeholder {
                        Theme.cardBackground
                    }
                    .loadDiskFileSynchronously()
                    .fade(duration: 0.15)
                    .cancelOnDisappear(true)
                    .downsampling(size: CGSize(width: rowHeight * 2, height: rowHeight * 2))
                    .cacheOriginalImage()
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
