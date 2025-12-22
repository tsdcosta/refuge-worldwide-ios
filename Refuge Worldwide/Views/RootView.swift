//
//  RootView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI
import UIKit

enum Tab: Int, Hashable, CaseIterable {
    case live = 0
    case schedule = 1
    case artists = 2
    case shows = 3

    var title: String {
        switch self {
        case .live: return "Live"
        case .schedule: return "Schedule"
        case .artists: return "Artists"
        case .shows: return "Shows"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .schedule: return "calendar"
        case .artists: return "person.2"
        case .shows: return "play.circle"
        }
    }
}

struct RootView: View {
    @State private var selectedTab: Tab = .live
    @State private var previousTab: Tab = .live
    @State private var scheduleNavigationPath = NavigationPath()
    @State private var artistsNavigationPath = NavigationPath()
    @State private var showsNavigationPath = NavigationPath()
    @State private var selectedShow: ShowItem?
    @State private var showsSearchMode = false
    @State private var showsSearchText = ""
    @State private var showsSearchResults: [ShowItem] = []
    @State private var showsGenreFilter: String?
    @ObservedObject private var radio = RadioPlayer.shared

    private func handleShowSelected(_ show: ShowItem) {
        selectedShow = show
        showsNavigationPath = NavigationPath()
        showsSearchMode = false
        switchTab(to: .shows)
    }

    private func handleArtistSelected(slug: String, name: String) {
        artistsNavigationPath = NavigationPath()
        artistsNavigationPath.append(ScheduleDestination.artistDetail(slug: slug, name: name))
        switchTab(to: .artists)
    }

    private func handleGenreSelected(_ genre: String) {
        showsNavigationPath = NavigationPath()
        showsSearchText = ""
        showsSearchResults = []
        showsGenreFilter = genre
        showsSearchMode = true

        // If no show is selected, try to use the currently playing show so overlay appears
        if selectedShow == nil, let playingShow = radio.currentPlayingShow {
            selectedShow = playingShow
        }

        switchTab(to: .shows)
    }

    private var slideDirection: Edge {
        selectedTab.rawValue > previousTab.rawValue ? .trailing : .leading
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                liveView
                    .zIndex(selectedTab == .live ? 1 : 0)
                    .opacity(selectedTab == .live ? 1 : 0)

                scheduleView
                    .zIndex(selectedTab == .schedule ? 1 : 0)
                    .opacity(selectedTab == .schedule ? 1 : 0)

                artistsView
                    .zIndex(selectedTab == .artists ? 1 : 0)
                    .opacity(selectedTab == .artists ? 1 : 0)

                showsView
                    .zIndex(selectedTab == .shows ? 1 : 0)
                    .opacity(selectedTab == .shows ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: selectedTab)

            CustomTabBar(selectedTab: tabSelection)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var liveView: some View {
        LiveView(
            onShowSelected: handleShowSelected,
            onArtistSelected: handleArtistSelected,
            onGenreSelected: handleGenreSelected
        )
        .offset(x: tabOffset(for: .live))
    }

    @ViewBuilder
    private var scheduleView: some View {
        ScheduleView(
            navigationPath: $scheduleNavigationPath,
            onShowSelected: handleShowSelected,
            onArtistSelected: handleArtistSelected,
            onGenreSelected: handleGenreSelected,
            onLiveShowSelected: { switchTab(to: .live) }
        )
        .offset(x: tabOffset(for: .schedule))
    }

    @ViewBuilder
    private var artistsView: some View {
        ArtistsView(
            navigationPath: $artistsNavigationPath,
            onShowSelected: handleShowSelected,
            onGenreSelected: handleGenreSelected
        )
        .offset(x: tabOffset(for: .artists))
    }

    @ViewBuilder
    private var showsView: some View {
        ShowsView(
            show: selectedShow,
            navigationPath: $showsNavigationPath,
            isSearchMode: $showsSearchMode,
            searchText: $showsSearchText,
            searchResults: $showsSearchResults,
            genreFilter: $showsGenreFilter,
            onShowSelected: handleShowSelected,
            onArtistSelected: handleArtistSelected,
            onGenreSelected: handleGenreSelected
        )
        .offset(x: tabOffset(for: .shows))
    }

    private func tabOffset(for tab: Tab) -> CGFloat {
        if tab == selectedTab {
            return 0
        }
        let screenWidth = UIScreen.main.bounds.width
        return tab.rawValue < selectedTab.rawValue ? -screenWidth : screenWidth
    }

    private func switchTab(to newTab: Tab) {
        previousTab = selectedTab
        selectedTab = newTab
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                // If tapping the same tab, pop to root
                if newTab == selectedTab {
                    if newTab == .schedule {
                        scheduleNavigationPath = NavigationPath()
                    } else if newTab == .artists {
                        artistsNavigationPath = NavigationPath()
                    } else if newTab == .shows {
                        if showsSearchMode {
                            showsSearchMode = false
                        } else {
                            showsNavigationPath = NavigationPath()
                            if let playingShow = radio.currentPlayingShow {
                                selectedShow = playingShow
                            }
                        }
                    }
                } else {
                    if newTab == .shows {
                        showsSearchMode = false
                        if let playingShow = radio.currentPlayingShow {
                            selectedShow = playingShow
                            showsNavigationPath = NavigationPath()
                        }
                    }
                    previousTab = selectedTab
                    selectedTab = newTab
                }
            }
        )
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Tab

    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, max(bottomSafeArea, 8))
        .background(Color.black)
    }
}

struct TabBarButton: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? Theme.orange : .gray)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
