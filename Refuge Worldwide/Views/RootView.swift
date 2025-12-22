//
//  RootView.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI
import UIKit

enum Tab: Hashable {
    case live
    case schedule
    case artists
    case shows
}

struct RootView: View {
    @State private var selectedTab: Tab = .live
    @State private var scheduleNavigationPath = NavigationPath()
    @State private var artistsNavigationPath = NavigationPath()
    @State private var showsNavigationPath = NavigationPath()
    @State private var selectedShow: ShowItem?
    @State private var showsSearchMode = false
    @State private var showsSearchText = ""
    @State private var showsSearchResults: [ShowItem] = []
    @ObservedObject private var radio = RadioPlayer.shared

    private func handleShowSelected(_ show: ShowItem) {
        selectedShow = show
        showsNavigationPath = NavigationPath()
        showsSearchMode = false
        selectedTab = .shows
    }

    private func handleArtistSelected(slug: String, name: String) {
        artistsNavigationPath = NavigationPath()
        artistsNavigationPath.append(ScheduleDestination.artistDetail(slug: slug, name: name))
        selectedTab = .artists
    }

    var body: some View {
        TabView(selection: tabSelection) {
            LiveView(
                onShowSelected: handleShowSelected,
                onArtistSelected: handleArtistSelected
            )
                .tabItem {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(Tab.live)

            ScheduleView(
                navigationPath: $scheduleNavigationPath,
                onShowSelected: handleShowSelected,
                onArtistSelected: handleArtistSelected,
                onLiveShowSelected: { selectedTab = .live }
            )
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(Tab.schedule)

            ArtistsView(
                navigationPath: $artistsNavigationPath,
                onShowSelected: handleShowSelected
            )
                .tabItem {
                    Label("Artists", systemImage: "person.2")
                }
                .tag(Tab.artists)

            ShowsView(
                show: selectedShow,
                navigationPath: $showsNavigationPath,
                isSearchMode: $showsSearchMode,
                searchText: $showsSearchText,
                searchResults: $showsSearchResults,
                onShowSelected: handleShowSelected,
                onArtistSelected: handleArtistSelected
            )
                .tabItem {
                    Label("Shows", systemImage: "play.circle")
                }
                .tag(Tab.shows)
        }
        .tint(Theme.orange) // Use orange accent for radio app
        .preferredColorScheme(.dark)
        .onAppear {
            configureTabBarAppearance()
            // Allow screen to lock during audio playback
            UIApplication.shared.isIdleTimerDisabled = false
        }
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
                        // If in search mode, dismiss it; otherwise show currently playing
                        if showsSearchMode {
                            showsSearchMode = false
                        } else {
                            showsNavigationPath = NavigationPath()
                            // Navigate to currently playing show if one exists
                            if let playingShow = radio.currentPlayingShow {
                                selectedShow = playingShow
                            }
                        }
                    }
                } else if newTab == .shows {
                    // When switching to Shows tab, dismiss search and show currently playing
                    showsSearchMode = false
                    if let playingShow = radio.currentPlayingShow {
                        selectedShow = playingShow
                        showsNavigationPath = NavigationPath()
                    }
                }
                selectedTab = newTab
            }
        )
    }

    private func configureTabBarAppearance() {
        // Configure tab bar appearance to match website design
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.gray,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        // Selected state - use orange accent
        let orangeColor = UIColor(red: 1.0, green: 0.576, blue: 0.0, alpha: 1.0) // #ff9300
        appearance.stackedLayoutAppearance.selected.iconColor = orangeColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: orangeColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
