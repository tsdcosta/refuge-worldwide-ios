//
//  EmbedPlayer.swift
//  Refuge Worldwide
//
//  Created by Tiago on 12/19/25.
//

import Foundation
import WebKit
import UIKit

enum EmbedPlatform {
    case soundcloud
    case mixcloud
}

/// Plays SoundCloud and Mixcloud tracks using their Widget APIs embedded in a hidden WKWebView
final class EmbedPlayer: NSObject, @unchecked Sendable {
    static let shared = EmbedPlayer()

    private var webView: WKWebView?
    private let stateLock = NSLock()
    private var _isPlaying = false
    private var _isBuffering = false
    private var _currentURL: URL?
    private var _currentPosition: Double = 0
    private var _duration: Double = 0
    private var _currentPlatform: EmbedPlatform?
    private var _needsRecreation = false
    private var _pendingResume = false

    var isPlaying: Bool {
        stateLock.withLock { _isPlaying }
    }

    var isBuffering: Bool {
        stateLock.withLock { _isBuffering }
    }

    var currentURL: URL? {
        stateLock.withLock { _currentURL }
    }

    var currentPosition: Double {
        stateLock.withLock { _currentPosition }
    }

    var duration: Double {
        stateLock.withLock { _duration }
    }

    var currentPlatform: EmbedPlatform? {
        stateLock.withLock { _currentPlatform }
    }

    var onStateChanged: (() -> Void)?
    var onProgressChanged: (() -> Void)?

    private override init() {
        super.init()
        setupAppLifecycleObservers()
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        // Mark that webview may need special handling on next resume
        let hasURL = stateLock.withLock { _currentURL != nil }
        if hasURL {
            stateLock.withLock { _needsRecreation = true }
            print("[EmbedPlayer] App entered background")
        }
    }

    @objc private func appDidBecomeActive() {
        // Check if there's a pending resume from lock screen
        let shouldResume = stateLock.withLock { _pendingResume }
        if shouldResume {
            print("[EmbedPlayer] App became active, executing pending resume")
            stateLock.withLock { _pendingResume = false }
            performResume()
        }
    }

    /// Check if a URL is a SoundCloud URL
    static func isSoundCloudURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("soundcloud.com")
    }

    /// Check if a URL is a Mixcloud URL
    static func isMixcloudURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("mixcloud.com")
    }

    /// Check if a URL is embeddable (SoundCloud or Mixcloud)
    static func isEmbeddableURL(_ url: URL) -> Bool {
        return isSoundCloudURL(url) || isMixcloudURL(url)
    }

    /// Play a SoundCloud or Mixcloud track URL
    func play(url: URL) {
        let platform: EmbedPlatform
        if EmbedPlayer.isSoundCloudURL(url) {
            platform = .soundcloud
        } else if EmbedPlayer.isMixcloudURL(url) {
            platform = .mixcloud
        } else {
            print("[EmbedPlayer] URL is not embeddable: \(url)")
            return
        }

        print("[EmbedPlayer] Play requested (\(platform)): \(url)")

        stateLock.withLock {
            _currentURL = url
            _isBuffering = true
            _isPlaying = true
            _currentPlatform = platform
            _currentPosition = 0
            _duration = 0
            _needsRecreation = false
            _pendingResume = false
        }
        onStateChanged?()

        DispatchQueue.main.async { [weak self] in
            self?.setupAndPlay(url: url, platform: platform)
        }
    }

    func pause() {
        print("[EmbedPlayer] Pause requested")

        let platform = currentPlatform
        DispatchQueue.main.async { [weak self] in
            switch platform {
            case .soundcloud:
                self?.webView?.evaluateJavaScript("widget.pause();", completionHandler: nil)
            case .mixcloud:
                self?.webView?.evaluateJavaScript("widget.pause();", completionHandler: nil)
            case .none:
                break
            }
        }

        stateLock.withLock {
            _isPlaying = false
            _isBuffering = false
        }
        onStateChanged?()
    }

    func resume() {
        print("[EmbedPlayer] Resume requested")

        // Check if app is active - if not, defer resume until it becomes active
        // WKWebView's WebContent process is suspended when app is not active,
        // so JS calls won't execute and audio won't play
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let appState = UIApplication.shared.applicationState
            if appState != .active {
                print("[EmbedPlayer] App not active (state: \(appState.rawValue)), deferring resume")
                self.stateLock.withLock { self._pendingResume = true }
                return
            }

            self.performResume()
        }
    }

    private func performResume() {
        let savedURL = currentURL
        let savedPosition = currentPosition
        let platform = currentPlatform

        stateLock.withLock {
            _isPlaying = true
            _isBuffering = true
        }
        onStateChanged?()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if webview exists and is attached
            guard let webView = self.webView, webView.superview != nil else {
                print("[EmbedPlayer] Webview invalid, recreating from saved state")
                self.stateLock.withLock { self._needsRecreation = false }
                if let url = savedURL {
                    self.recreateAndSeek(url: url, position: savedPosition, platform: platform)
                }
                return
            }

            // Try to resume via JS - use a test call first to check if widget is alive
            webView.evaluateJavaScript("typeof widget !== 'undefined'") { [weak self] result, error in
                guard let self = self else { return }

                let widgetExists = (result as? Bool) == true

                if let error = error {
                    // Real JS errors (not just type bridging issues) indicate dead webview
                    let nsError = error as NSError
                    // WKErrorJavaScriptResultTypeIsUnsupported = 5, this is OK
                    // WKErrorWebContentProcessTerminated = 9, WKErrorWebViewInvalidated = 12 are fatal
                    if nsError.domain == "WKErrorDomain" && (nsError.code == 9 || nsError.code == 12) {
                        print("[EmbedPlayer] Webview terminated/invalidated, recreating")
                        self.stateLock.withLock { self._needsRecreation = false }
                        if let url = savedURL {
                            self.recreateAndSeek(url: url, position: savedPosition, platform: platform)
                        }
                        return
                    }
                }

                if !widgetExists {
                    print("[EmbedPlayer] Widget not found in JS context, recreating")
                    self.stateLock.withLock { self._needsRecreation = false }
                    if let url = savedURL {
                        self.recreateAndSeek(url: url, position: savedPosition, platform: platform)
                    }
                    return
                }

                // Widget exists, call play
                print("[EmbedPlayer] Widget alive, calling play()")
                self.stateLock.withLock { self._needsRecreation = false }
                webView.evaluateJavaScript("widget.play();", completionHandler: nil)
            }
        }
    }

    private func recreateAndSeek(url: URL, position: Double, platform: EmbedPlatform?) {
        guard let platform = platform else {
            // Determine platform from URL if not saved
            if EmbedPlayer.isSoundCloudURL(url) {
                setupAndPlay(url: url, platform: .soundcloud)
            } else if EmbedPlayer.isMixcloudURL(url) {
                setupAndPlay(url: url, platform: .mixcloud)
            }
            return
        }

        setupAndPlay(url: url, platform: platform)

        // Seek to saved position after a delay to allow widget to initialize
        if position > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.seekTo(position: position)
            }
        }
    }

    func stop() {
        print("[EmbedPlayer] Stop requested")

        let platform = currentPlatform
        DispatchQueue.main.async { [weak self] in
            switch platform {
            case .soundcloud:
                self?.webView?.evaluateJavaScript("widget.pause();", completionHandler: nil)
            case .mixcloud:
                self?.webView?.evaluateJavaScript("widget.pause();", completionHandler: nil)
            case .none:
                break
            }
        }

        stateLock.withLock {
            _isPlaying = false
            _isBuffering = false
            _currentURL = nil
            _currentPosition = 0
            _duration = 0
            _currentPlatform = nil
            _needsRecreation = false
            _pendingResume = false
        }
        onStateChanged?()
    }

    func seekTo(position: Double) {
        let platform = currentPlatform
        print("[EmbedPlayer] Seek to \(position)s")

        DispatchQueue.main.async { [weak self] in
            switch platform {
            case .soundcloud:
                let positionMs = Int(position * 1000)
                self?.webView?.evaluateJavaScript("widget.seekTo(\(positionMs));", completionHandler: nil)
            case .mixcloud:
                self?.webView?.evaluateJavaScript("widget.seek(\(position));", completionHandler: nil)
            case .none:
                break
            }
        }
    }

    private func setupAndPlay(url: URL, platform: EmbedPlatform) {
        // Clean up existing webview
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "embedPlayer")
        webView?.removeFromSuperview()

        // Configure webview for background audio
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Add message handler for JavaScript callbacks
        config.userContentController.add(self, name: "embedPlayer")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        webView.isHidden = true
        self.webView = webView

        // Attach to window so audio can play
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.addSubview(webView)
        }

        // Create the widget HTML based on platform
        let html: String
        let baseURL: URL?

        switch platform {
        case .soundcloud:
            html = createSoundCloudWidgetHTML(trackURL: url.absoluteString)
            baseURL = URL(string: "https://soundcloud.com")
        case .mixcloud:
            html = createMixcloudWidgetHTML(trackURL: url)
            baseURL = URL(string: "https://www.mixcloud.com")
        }

        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func createSoundCloudWidgetHTML(trackURL: String) -> String {
        // URL-encode the track URL for use in the widget src
        let encodedURL = trackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trackURL

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body style="margin:0;padding:0;">
            <iframe id="sc-widget"
                    width="100%"
                    height="166"
                    scrolling="no"
                    frameborder="no"
                    allow="autoplay"
                    src="https://w.soundcloud.com/player/?url=\(encodedURL)&auto_play=true&hide_related=true&show_comments=false&show_user=true&show_reposts=false&show_teaser=false">
            </iframe>
            <script src="https://w.soundcloud.com/player/api.js"></script>
            <script>
                var widget = SC.Widget(document.getElementById('sc-widget'));

                widget.bind(SC.Widget.Events.READY, function() {
                    console.log('Widget ready');
                    widget.getDuration(function(duration) {
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'duration', duration: duration});
                    });
                    widget.play();
                });

                widget.bind(SC.Widget.Events.PLAY, function() {
                    console.log('Playing');
                    window.webkit.messageHandlers.embedPlayer.postMessage({event: 'play'});
                });

                widget.bind(SC.Widget.Events.PAUSE, function() {
                    console.log('Paused');
                    window.webkit.messageHandlers.embedPlayer.postMessage({event: 'pause'});
                });

                widget.bind(SC.Widget.Events.FINISH, function() {
                    console.log('Finished');
                    window.webkit.messageHandlers.embedPlayer.postMessage({event: 'finish'});
                });

                widget.bind(SC.Widget.Events.PLAY_PROGRESS, function(e) {
                    window.webkit.messageHandlers.embedPlayer.postMessage({
                        event: 'progress',
                        position: e.currentPosition,
                        duration: e.loadedProgress ? e.loadedProgress : 0
                    });
                });

                widget.bind(SC.Widget.Events.ERROR, function(e) {
                    console.log('Error:', e);
                    window.webkit.messageHandlers.embedPlayer.postMessage({event: 'error', data: e});
                });
            </script>
        </body>
        </html>
        """
    }

    private func createMixcloudWidgetHTML(trackURL: URL) -> String {
        // Use the full URL for the feed parameter (URL-encoded)
        let fullURL = trackURL.absoluteString
        let encodedFeed = fullURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fullURL

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body style="margin:0;padding:0;">
            <iframe id="mc-widget"
                    width="100%"
                    height="120"
                    frameborder="0"
                    allow="autoplay"
                    src="https://www.mixcloud.com/widget/iframe/?hide_cover=1&autoplay=1&feed=\(encodedFeed)">
            </iframe>
            <script src="https://widget.mixcloud.com/media/js/widgetApi.js"></script>
            <script>
                var widget = Mixcloud.PlayerWidget(document.getElementById('mc-widget'));

                widget.ready.then(function() {
                    console.log('Mixcloud widget ready');

                    widget.getDuration().then(function(duration) {
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'duration', duration: duration * 1000});
                    });

                    widget.events.play.on(function() {
                        console.log('Mixcloud playing');
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'play'});
                    });

                    widget.events.pause.on(function() {
                        console.log('Mixcloud paused');
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'pause'});
                    });

                    widget.events.ended.on(function() {
                        console.log('Mixcloud ended');
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'finish'});
                    });

                    widget.events.progress.on(function(position, duration) {
                        window.webkit.messageHandlers.embedPlayer.postMessage({
                            event: 'progress',
                            position: position * 1000,
                            duration: duration * 1000
                        });
                    });

                    widget.events.error.on(function(e) {
                        console.log('Mixcloud error:', e);
                        window.webkit.messageHandlers.embedPlayer.postMessage({event: 'error', data: e});
                    });

                    // Auto-play with delay to ensure widget is fully initialized
                    // The ready promise resolves before internal state is complete
                    setTimeout(function() {
                        widget.play();
                    }, 500);
                });
            </script>
        </body>
        </html>
        """
    }

    private func updateState(playing: Bool, buffering: Bool) {
        stateLock.withLock {
            _isPlaying = playing
            _isBuffering = buffering
        }
        onStateChanged?()
    }
}

// MARK: - WKNavigationDelegate

extension EmbedPlayer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[EmbedPlayer] WebView finished loading")
        // Widget should auto-play, update state
        updateState(playing: true, buffering: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[EmbedPlayer] WebView failed: \(error)")
        updateState(playing: false, buffering: false)
    }
}

// MARK: - WKScriptMessageHandler

extension EmbedPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }

        // Capture current platform once (thread-safe)
        let platform = stateLock.withLock { _currentPlatform }

        switch event {
        case "play":
            updateState(playing: true, buffering: false)

        case "pause", "finish", "error":
            updateState(playing: false, buffering: false)

        case "duration":
            if let durationMs = body["duration"] as? Double {
                stateLock.withLock {
                    _duration = durationMs / 1000.0
                }
            }

        case "progress":
            if let positionMs = body["position"] as? Double {
                stateLock.withLock {
                    _currentPosition = positionMs / 1000.0
                }
                // Also update duration from progress events (especially important for Mixcloud
                if platform == .mixcloud, let durationMs = body["duration"] as? Double, durationMs > 0 {
                    stateLock.withLock {
                        _duration = durationMs / 1000.0
                    }
                }
                onProgressChanged?()
            }
        default:
            break
        }
    }
}
