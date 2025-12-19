//
//  AppDelegate.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import UIKit
import AVFoundation

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

        print("[AppDelegate] Application did finish launching")
        return true
    }
}
