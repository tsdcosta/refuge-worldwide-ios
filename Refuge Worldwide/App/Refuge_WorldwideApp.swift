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

    @State private var splashOpacity: Double = 1.0

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .preferredColorScheme(.dark)

                ZStack {
                    Color.white.ignoresSafeArea()
                    Image("navigation-smile")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                }
                .opacity(splashOpacity)
                .animation(.easeOut(duration: 0.3), value: splashOpacity)
                .allowsHitTesting(splashOpacity > 0)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    splashOpacity = 0
                }
            }
        }
    }
}
