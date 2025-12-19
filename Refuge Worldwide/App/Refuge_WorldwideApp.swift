//
//  Refuge_WorldwideApp.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import SwiftUI

@main
struct RefugeRadioApp: App {
    // Use AppDelegate for early audio session configuration
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Keep a reference to RadioPlayer to ensure it's initialized early
    // This sets up the remote command center
    private let radioPlayer = RadioPlayer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
