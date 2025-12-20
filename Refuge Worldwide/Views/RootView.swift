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
    case shows
}

struct RootView: View {
    @State private var selectedTab: Tab = .live
    @State private var scheduleNavigationPath = NavigationPath()
    @State private var showsNavigationPath = NavigationPath()
    @State private var selectedShow: ShowItem?

    var body: some View {
        TabView(selection: tabSelection) {
            LiveView(onShowSelected: { show in
                selectedShow = show
                showsNavigationPath = NavigationPath()
                selectedTab = .shows
            })
                .tabItem {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(Tab.live)

            ScheduleView(
                navigationPath: $scheduleNavigationPath,
                onShowSelected: { show in
                    selectedShow = show
                    showsNavigationPath = NavigationPath()
                    selectedTab = .shows
                }
            )
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(Tab.schedule)

            ShowsView(
                show: selectedShow,
                navigationPath: $showsNavigationPath,
                onShowSelected: { show in
                    selectedShow = show
                    showsNavigationPath = NavigationPath()
                }
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
                    } else if newTab == .shows {
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
