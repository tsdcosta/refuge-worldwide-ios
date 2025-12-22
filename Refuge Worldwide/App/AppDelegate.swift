//
//  AppDelegate.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import UIKit
import AVFoundation
import Kingfisher

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure audio session ONCE at the earliest possible moment
        // This is critical for background audio to work
        AudioEngine.shared.configureAudioSession()

        // Begin receiving remote control events
        application.beginReceivingRemoteControlEvents()

        // Configure Kingfisher for optimal scroll performance
        configureImageLoading()

        print("[AppDelegate] Application did finish launching")

        return true
    }

    private func configureImageLoading() {
        // Limit concurrent downloads to reduce contention during fast scrolling
        ImageDownloader.default.downloadTimeout = 15
        ImageDownloader.default.sessionConfiguration.httpMaximumConnectionsPerHost = 6

        // Disk cache: 200MB, 7 days expiration
        let cache = ImageCache.default
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(7)

        // Memory cache: use generous defaults, system handles pressure automatically
        // Don't set restrictive countLimit - let Kingfisher manage based on memory pressure
    }
}
