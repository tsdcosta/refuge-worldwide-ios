//
//  LiveView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI

struct LiveView: View {
    var onShowSelected: ((ShowItem) -> Void)?
    var onArtistSelected: ((String, String) -> Void)?
    var onGenreSelected: ((String) -> Void)?

    @ObservedObject private var radio = RadioPlayer.shared
    @ObservedObject private var liveService = LiveShowService.shared
    @State private var navigationPath = NavigationPath()

    private var liveShow: ShowItem? { liveService.liveShow }
    private var liveDescription: [String] { liveService.liveDescription }
    private var liveGenres: [String] { liveService.liveGenres }

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
                    // Cover image with live indicator and play button overlay
                    ZStack {
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

                        // Live indicator - top left, only show when live stream is playing (not buffering)
                        if radio.isPlaying && radio.isLiveStream && !radio.isBuffering {
                            VStack {
                                HStack {
                                    LiveIndicator()
                                        .padding(Theme.Spacing.base)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }

                        // Play/Stop button - bottom left
                        VStack {
                            Spacer()
                            HStack {
                                LivePlayButton(
                                    isPlaying: radio.isPlaying && radio.isLiveStream,
                                    isBuffering: radio.isBuffering && radio.isLiveStream
                                ) {
                                    togglePlayback()
                                }
                                .padding(Theme.Spacing.base)
                                Spacer()
                            }
                        }
                    }

                    if let show = liveShow {
                        VStack(spacing: Theme.Spacing.base) {
                            // Time (centered) with Share icon on right
                            HStack {
                                Spacer()
                                if !timeString.isEmpty {
                                    Text(timeString)
                                        .font(.lightBody(size: Theme.Typography.bodySmall))
                                        .foregroundColor(Theme.secondaryText)
                                }
                                Spacer()
                            }
                            .overlay(alignment: .trailing) {
                                // Share icon - use /radio for repeats, /radio/slug for live shows
                                let shareURL: URL = {
                                    if !show.slug.isEmpty,
                                       let encoded = show.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                                        return URL(string: "https://refugeworldwide.com/radio/\(encoded)")!
                                    }
                                    return URL(string: "https://refugeworldwide.com/radio")!
                                }()
                                ShareLink(item: shareURL) {
                                    ShareIconView(size: 20, color: Theme.foreground)
                                }
                            }
                            .padding(.top, Theme.Spacing.lg)

                            // Title - serif heading style
                            Text(show.title)
                                .font(.serifHeading(size: Theme.Typography.headingBase))
                                .foregroundColor(Theme.foreground)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            // Genre badges - website style (centered, tappable)
                            if !liveGenres.isEmpty {
                                HStack(spacing: Theme.Spacing.sm) {
                                    ForEach(liveGenres, id: \.self) { genre in
                                        Button {
                                            onGenreSelected?(genre)
                                        } label: {
                                            GenreBadge(genre: genre)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }

                            // Artists - tappable links
                            if let artists = show.artistsCollection?.items, !artists.isEmpty {
                                ArtistLinksView(artists: artists, onArtistSelected: onArtistSelected)
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
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
            .background(Theme.background)
            .task {
                liveService.addObserver()
                await liveService.refresh()
            }
            .onDisappear {
                liveService.removeObserver()
            }
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

// MARK: - Live Play Button Component (simple icon on image)

struct LivePlayButton: View {
    let isPlaying: Bool
    let isBuffering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBuffering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.foreground))
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Theme.foreground)
                }
            }
            .frame(width: 50, height: 50)
            .background(Theme.background.opacity(0.8))
            .clipShape(Circle())
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
