//
//  SoundCloudPlayer.swift
//  Refuge Worldwide
//
//  Created by Tiago on 12/19/25.
//

import Foundation
import WebKit
import AVFoundation
import UIKit

/// Plays SoundCloud tracks using the SoundCloud Widget API embedded in a hidden WKWebView
final class SoundCloudPlayer: NSObject, @unchecked Sendable {
    static let shared = SoundCloudPlayer()

    private var webView: WKWebView?
    private let stateLock = NSLock()
    private var _isPlaying = false
    private var _isBuffering = false
    private var _currentURL: URL?

    var isPlaying: Bool {
        stateLock.withLock { _isPlaying }
    }

    var isBuffering: Bool {
        stateLock.withLock { _isBuffering }
    }

    var currentURL: URL? {
        stateLock.withLock { _currentURL }
    }

    var onStateChanged: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Check if a URL is a SoundCloud URL
    static func isSoundCloudURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("soundcloud.com")
    }

    /// Play a SoundCloud track URL
    func play(url: URL) {
        print("[SoundCloudPlayer] Play requested: \(url)")

        stateLock.withLock {
            _currentURL = url
            _isBuffering = true
            _isPlaying = true
        }
        onStateChanged?()

        DispatchQueue.main.async { [weak self] in
            self?.setupAndPlay(url: url)
        }
    }

    func stop() {
        print("[SoundCloudPlayer] Stop requested")

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("widget.pause();", completionHandler: nil)
        }

        stateLock.withLock {
            _isPlaying = false
            _isBuffering = false
            _currentURL = nil
        }
        onStateChanged?()
    }

    private func setupAndPlay(url: URL) {
        // Clean up existing webview
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "soundcloud")
        webView?.removeFromSuperview()

        // Configure webview for background audio
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Add message handler for JavaScript callbacks
        config.userContentController.add(self, name: "soundcloud")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        webView.isHidden = true
        self.webView = webView

        // Attach to window so audio can play
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.addSubview(webView)
        }

        // Create the widget HTML - use the raw URL without extra encoding
        let html = createWidgetHTML(trackURL: url.absoluteString)

        webView.loadHTMLString(html, baseURL: URL(string: "https://soundcloud.com"))
    }

    private func createWidgetHTML(trackURL: String) -> String {
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
                    widget.play();
                });

                widget.bind(SC.Widget.Events.PLAY, function() {
                    console.log('Playing');
                    window.webkit.messageHandlers.soundcloud.postMessage({event: 'play'});
                });

                widget.bind(SC.Widget.Events.PAUSE, function() {
                    console.log('Paused');
                    window.webkit.messageHandlers.soundcloud.postMessage({event: 'pause'});
                });

                widget.bind(SC.Widget.Events.FINISH, function() {
                    console.log('Finished');
                    window.webkit.messageHandlers.soundcloud.postMessage({event: 'finish'});
                });

                widget.bind(SC.Widget.Events.ERROR, function(e) {
                    console.log('Error:', e);
                    window.webkit.messageHandlers.soundcloud.postMessage({event: 'error', data: e});
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

extension SoundCloudPlayer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[SoundCloudPlayer] WebView finished loading")
        // Widget should auto-play, update state
        updateState(playing: true, buffering: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[SoundCloudPlayer] WebView failed: \(error)")
        updateState(playing: false, buffering: false)
    }
}

// MARK: - WKScriptMessageHandler

extension SoundCloudPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }

        print("[SoundCloudPlayer] Received event: \(event)")

        switch event {
        case "play":
            updateState(playing: true, buffering: false)
        case "pause", "finish":
            updateState(playing: false, buffering: false)
        case "error":
            updateState(playing: false, buffering: false)
        default:
            break
        }
    }
}
