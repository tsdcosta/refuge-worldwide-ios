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
    @Binding var isSearchMode: Bool
    @Binding var searchText: String
    @Binding var searchResults: [ShowItem]
    var onShowSelected: ((ShowItem) -> Void)?
    var onArtistSelected: ((String, String) -> Void)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let show = show {
                    ShowDetailContent(
                        show: show,
                        navigationPath: $navigationPath,
                        isSearchMode: $isSearchMode,
                        searchText: $searchText,
                        searchResults: $searchResults,
                        onShowSelected: onShowSelected,
                        onArtistSelected: onArtistSelected
                    )
                } else {
                    ShowSearchView(
                        searchText: $searchText,
                        searchResults: $searchResults,
                        onShowSelected: onShowSelected
                    )
                }
            }
            .navigationDestination(for: ScheduleDestination.self) { destination in
                switch destination {
                case .showDetail(let show):
                    ShowDetailContent(
                        show: show,
                        navigationPath: $navigationPath,
                        isSearchMode: .constant(false),
                        searchText: .constant(""),
                        searchResults: .constant([]),
                        onShowSelected: onShowSelected,
                        onArtistSelected: onArtistSelected
                    )
                case .artistDetail(let slug, let name):
                    ArtistDetailView(artistSlug: slug, artistName: name, navigationPath: $navigationPath, onShowSelected: onShowSelected)
                }
            }
        }
    }
}

// MARK: - Show Search View

struct ShowSearchView: View {
    @Binding var searchText: String
    @Binding var searchResults: [ShowItem]
    var onShowSelected: ((ShowItem) -> Void)?

    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private var hasTyped: Bool {
        !searchText.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchFocused = false
                    }

                VStack(spacing: 0) {
                    if hasTyped {
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.top + Theme.Spacing.xl)
                    } else {
                        Spacer()
                    }

                    // Search bar - white horizontal line
                    VStack(spacing: 0) {
                        HStack {
                            TextField("", text: $searchText, prompt: Text("Search shows").foregroundColor(Theme.secondaryText))
                                .font(.lightBody(size: Theme.Typography.bodyBase))
                                .foregroundColor(Theme.foreground)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                                .focused($isSearchFocused)

                            if isSearching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                                    .scaleEffect(0.8)
                            } else if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.base)
                        .padding(.bottom, Theme.Spacing.sm)

                        // White horizontal line
                        Rectangle()
                            .fill(Theme.foreground)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    if hasTyped {
                        // Search results
                        if isSearching && searchResults.isEmpty {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                            Spacer()
                        } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                            Spacer()
                            Text("No shows found")
                                .font(.lightBody(size: Theme.Typography.bodyBase))
                                .foregroundColor(Theme.secondaryText)
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, show in
                                        Button {
                                            onShowSelected?(show)
                                        } label: {
                                            SearchResultRow(show: show)
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        if index < searchResults.count - 1 {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.1))
                                                .frame(height: 1)
                                                .padding(.horizontal, Theme.Spacing.lg)
                                        }
                                    }
                                }
                                .padding(.top, Theme.Spacing.lg)
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasTyped)
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()

            if newValue.isEmpty {
                searchResults = []
                isSearching = false
                return
            }

            isSearching = true

            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                await performSearch(query: newValue)
            }
        }
    }

    private func performSearch(query: String) async {
        do {
            let results = try await RefugeAPI.shared.searchShows(query: query)
            if !Task.isCancelled && searchText == query {
                searchResults = results
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
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let show: ShowItem
    private let rowHeight: CGFloat = 80

    private var formattedDate: String? {
        guard let date = show.date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Cover image
            if let url = show.coverImage?.url {
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

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(show.title.replacingOccurrences(of: #" - .*$"#, with: "", options: .regularExpression))
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

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .padding(.trailing, Theme.Spacing.md)
        }
        .padding(.leading, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: rowHeight)
        .background(Theme.background)
    }
}

// MARK: - Show Detail Content

struct ShowDetailContent: View {
    let show: ShowItem
    @Binding var navigationPath: NavigationPath
    @Binding var isSearchMode: Bool
    @Binding var searchText: String
    @Binding var searchResults: [ShowItem]
    var onShowSelected: ((ShowItem) -> Void)?
    var onArtistSelected: ((String, String) -> Void)?

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

    private var isThisPaused: Bool {
        guard let url = streamURL else { return false }
        return radio.isPausedURL(url)
    }

    private var isThisBuffering: Bool {
        guard let url = streamURL else { return false }
        return radio.isBuffering && radio.currentPlayingURL == url
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Cover image - full width, square
                    if let url = show.coverImage?.url {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                KFImage(url)
                                    .loadDiskFileSynchronously()
                                    .cacheOriginalImage()
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
                        ArtistLinksView(artists: artists, onArtistSelected: onArtistSelected)
                    }
                    
                    // Play button - prominent, centered
                    if let link = mixcloudLink, !link.isEmpty {
                        Button {
                            guard let url = streamURL else { return }
                            if isThisPlaying {
                                radio.pause()
                            } else if isThisPaused {
                                radio.resume()
                            } else {
                                radio.playURL(url, title: show.title, artworkURL: show.coverImage?.url, show: show)
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
                                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(Theme.background)
                                        .offset(x: isThisPlaying ? 0 : 2)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, Theme.Spacing.lg)

                        // Seek bar - visible when playing or paused
                        if (isThisPlaying || isThisPaused) && radio.canSeek {
                            SeekBarView(
                                position: Binding(
                                    get: { radio.currentPosition },
                                    set: { radio.seekTo(position: $0) }
                                ),
                                duration: radio.duration
                            )
                            .padding(.top, Theme.Spacing.md)
                        }
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
                                    RelatedShowCard(show: relatedShow, onArtistSelected: onArtistSelected)
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

            // Search overlay (placed before pill so pill stays on top)
            if isSearchMode {
                ShowSearchOverlay(
                    searchText: $searchText,
                    searchResults: $searchResults,
                    onShowSelected: { selectedShow in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearchMode = false
                        }
                        onShowSelected?(selectedShow)
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSearchMode = false
                        }
                    }
                )
                .transition(.opacity)
            }

            // Search icon pill - top right, floating (on top of everything)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchMode.toggle()
                }
            } label: {
                SearchPill(isActive: isSearchMode)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, Theme.Spacing.base)
            .padding(.top, Theme.Spacing.base)
        }
        .background(Theme.background)
        .onChange(of: show.slug) { _, _ in
            // Reset search mode when navigating to a different show
            isSearchMode = false
        }
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

// MARK: - Seek Bar

struct SeekBarView: View {
    @Binding var position: Double
    let duration: Double

    @State private var isDragging = false
    @State private var dragPosition: Double = 0

    private var displayPosition: Double {
        isDragging ? dragPosition : position
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return displayPosition / duration
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Slider track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    // Progress track
                    Capsule()
                        .fill(Theme.foreground)
                        .frame(width: max(0, geometry.size.width * progress), height: 4)

                    // Drag handle
                    Circle()
                        .fill(Theme.foreground)
                        .frame(width: 16, height: 16)
                        .offset(x: max(0, min(geometry.size.width - 16, geometry.size.width * progress - 8)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                            dragPosition = newProgress * duration
                        }
                        .onEnded { value in
                            let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                            position = newProgress * duration
                            isDragging = false
                        }
                )
            }
            .frame(height: 16)

            // Time labels
            HStack {
                Text(formatTime(displayPosition))
                    .font(.lightBody(size: Theme.Typography.caption))
                    .foregroundColor(Theme.secondaryText)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(duration))
                    .font(.lightBody(size: Theme.Typography.caption))
                    .foregroundColor(Theme.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Search Pill (similar style to LetterPill)

struct SearchPill: View {
    var isActive: Bool = false

    var body: some View {
        Image(systemName: isActive ? "xmark" : "magnifyingglass")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.black)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black, radius: 0, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 1.5)
            )
    }
}

// MARK: - Search Overlay (appears on top of show detail)

struct ShowSearchOverlay: View {
    @Binding var searchText: String
    @Binding var searchResults: [ShowItem]
    var onShowSelected: ((ShowItem) -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top area with search bar
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: Theme.Spacing.xl + 44) // Space for pill

                // Search bar - white horizontal line
                VStack(spacing: 0) {
                    HStack {
                        TextField("", text: $searchText, prompt: Text("Search shows").foregroundColor(Theme.secondaryText))
                            .font(.lightBody(size: Theme.Typography.bodyBase))
                            .foregroundColor(Theme.foreground)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .focused($isSearchFocused)

                        if isSearching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                                .scaleEffect(0.8)
                        } else if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Theme.secondaryText)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.base)
                    .padding(.bottom, Theme.Spacing.sm)

                    // White horizontal line
                    Rectangle()
                        .fill(Theme.foreground)
                        .frame(height: 1)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }

            // Search results
            if isSearching && searchResults.isEmpty {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                Spacer()
            } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                Spacer()
                Text("No shows found")
                    .font(.lightBody(size: Theme.Typography.bodyBase))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
            } else if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, show in
                            Button {
                                onShowSelected?(show)
                            } label: {
                                SearchResultRow(show: show)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if index < searchResults.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 1)
                                    .padding(.horizontal, Theme.Spacing.lg)
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.lg)
                }
            } else {
                Spacer()
                Text("Type to search for shows")
                    .font(.lightBody(size: Theme.Typography.bodyBase))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()

            if newValue.isEmpty {
                searchResults = []
                isSearching = false
                return
            }

            isSearching = true

            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                await performSearch(query: newValue)
            }
        }
    }

    private func performSearch(query: String) async {
        do {
            let results = try await RefugeAPI.shared.searchShows(query: query)
            if !Task.isCancelled && searchText == query {
                searchResults = results
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
}
