//
//  AppDelegate.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import UIKit
import AVFoundation
import CoreText

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

        // Register bundled fonts programmatically (robust and avoids Info.plist path issues)
        registerBundledFonts()

        return true
    }

    private func registerBundledFonts() {
        let fontFiles = ["bely-display.otf", "VisueltLight.otf", "VisueltMedium.otf", "ABCArizonaFlare.otf"]

        for fileName in fontFiles {
            var foundURL: URL? = nil

            // Try resource in 'Fonts' subdirectory
            if let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Fonts") {
                foundURL = url
            }

            // Try resource in bundle root
            if foundURL == nil {
                if let url = Bundle.main.url(forResource: fileName, withExtension: nil) {
                    foundURL = url
                }
            }

            // Fallback: search all otf resources returned as a non-optional array
            if foundURL == nil {
                let resourcePaths = Bundle.main.paths(forResourcesOfType: "otf", inDirectory: nil)
                for path in resourcePaths {
                    if path.hasSuffix(fileName) {
                        foundURL = URL(fileURLWithPath: path)
                        break
                    }
                }
            }

            guard let fontURL = foundURL else {
                print("[FontRegister] Font file not found in bundle: \(fileName)")
                continue
            }

            // Determine PostScript names from the font file descriptors
            var alreadyAvailable = false
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor] {
                for desc in descriptors {
                    // Create a CTFont from the descriptor and get its PostScript name
                    let ctFont = CTFontCreateWithFontDescriptor(desc, 12.0, nil)
                    let psNameCF = CTFontCopyPostScriptName(ctFont)
                    let psName = psNameCF as String
                    if UIFont(name: psName, size: 12) != nil {
                        print("[FontRegister] Font already available in system: \(psName). Skipping registration for file: \(fileName)")
                        alreadyAvailable = true
                        break
                    }
                }
            }

            if alreadyAvailable { continue }

            var registrationError: Unmanaged<CFError>?
            let succeeded = CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, &registrationError)
            if succeeded {
                print("[FontRegister] Registered font file: \(fileName)")
            } else if let cfErr = registrationError?.takeRetainedValue() {
                // Convert CFError to NSError in a safe way
                let nsErr = (cfErr as Error) as NSError
                if nsErr.code == 105 {
                    print("[FontRegister] Font already registered (CTFontManager says so): \(fileName) (OK)")
                } else {
                    print("[FontRegister] Failed to register \(fileName): \(nsErr.localizedDescription) (code: \(nsErr.code))")
                }
            } else {
                print("[FontRegister] Failed to register \(fileName): unknown error")
            }
        }
    }
}
