//
//  RadioPlayer.swift
//  Refuge Worldwide
//
//  Created by Tiago Costa on 12/18/25.
//

import AVFoundation
import MediaPlayer
import UIKit
import Combine

// MARK: - Audio Engine (runs outside MainActor for background operation)

final class AudioEngine: NSObject, @unchecked Sendable {
    static let shared = AudioEngine()

    private let liveStreamURL = URL(string: "https://streaming.radio.co/s3699c5e49/listen")!

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?

    // Thread-safe state using a lock
    private let stateLock = NSLock()
    private var _isPlaying = false
    private var _isBuffering = false
    private var _playbackIntent = false
    private var _currentStreamURL: URL?
    private var _isLiveStream = true

    var isPlaying: Bool {
        stateLock.withLock { _isPlaying }
    }

    var isBuffering: Bool {
        stateLock.withLock { _isBuffering }
    }

    var playbackIntent: Bool {
        get { stateLock.withLock { _playbackIntent } }
        set { stateLock.withLock { _playbackIntent = newValue } }
    }

    var currentStreamURL: URL? {
        stateLock.withLock { _currentStreamURL }
    }

    var isLiveStream: Bool {
        stateLock.withLock { _isLiveStream }
    }

    // Callback for state changes (will be called on arbitrary queue)
    var onStateChanged: (() -> Void)?

    private override init() {
        super.init()
        setupNotifications()
    }

    // MARK: - Audio Session (call once at app launch from AppDelegate)

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("[AudioEngine] Audio session configured - category: \(session.category.rawValue)")
        } catch {
            print("[AudioEngine] Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("[AudioEngine] Interruption began - stopping playback")
            // Stop playback completely when another app plays audio
            stop()

        case .ended:
            print("[AudioEngine] Interruption ended")
            // Don't auto-resume - user needs to manually restart

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable {
            print("[AudioEngine] Audio route unavailable - stopping")
            stop()
        }
    }

    // MARK: - Playback Control

    func play() {
        playLiveStream()
    }

    func playLiveStream() {
        print("[AudioEngine] Play live stream requested")
        playbackIntent = true

        stateLock.withLock {
            _currentStreamURL = liveStreamURL
            _isLiveStream = true
        }

        if player == nil {
            createPlayer()
        } else {
            createFreshPlayerItem()
        }

        player?.play()
        updateState(playing: true, buffering: true)
    }

    func playURL(_ url: URL) {
        print("[AudioEngine] Play URL requested: \(url)")
        playbackIntent = true

        stateLock.withLock {
            _currentStreamURL = url
            _isLiveStream = false
        }

        if player == nil {
            createPlayer()
        } else {
            createFreshPlayerItem()
        }

        player?.play()
        updateState(playing: true, buffering: true)
    }

    func stop() {
        print("[AudioEngine] Stop requested")
        playbackIntent = false
        player?.pause()
        stateLock.withLock {
            _currentStreamURL = nil
        }
        updateState(playing: false, buffering: false)
    }

    func toggle() {
        if playbackIntent {
            stop()
        } else {
            play()
        }
    }

    // MARK: - Player Setup

    private func createPlayer() {
        player = AVPlayer()
        player?.automaticallyWaitsToMinimizeStalling = true

        // Observe time control status
        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, _ in
            self?.handleTimeControlStatusChange(player.timeControlStatus)
        }

        print("[AudioEngine] Created AVPlayer")
        createFreshPlayerItem()
    }

    private func createFreshPlayerItem() {
        itemStatusObserver?.invalidate()

        guard let url = currentStreamURL else {
            print("[AudioEngine] No URL to play")
            return
        }

        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.preferredForwardBufferDuration = 2

        itemStatusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            self?.handleItemStatusChange(item.status)
        }

        player?.replaceCurrentItem(with: playerItem)
        print("[AudioEngine] Created fresh player item for: \(url)")
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            print("[AudioEngine] Status: Playing")
            updateState(playing: true, buffering: false)

        case .paused:
            print("[AudioEngine] Status: Paused (intent: \(playbackIntent))")
            // Only update state if user actually stopped
            if !playbackIntent {
                updateState(playing: false, buffering: false)
            }
            // Don't try to auto-resume here - that causes the loop

        case .waitingToPlayAtSpecifiedRate:
            let reason = player?.reasonForWaitingToPlay?.rawValue ?? "unknown"
            print("[AudioEngine] Status: Buffering - reason: \(reason)")
            if playbackIntent {
                updateState(playing: true, buffering: true)
            }

        @unknown default:
            break
        }
    }

    private func handleItemStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("[AudioEngine] Player item ready")
            if playbackIntent {
                player?.play()
            }

        case .failed:
            let error = playerItem?.error?.localizedDescription ?? "unknown"
            print("[AudioEngine] Player item failed: \(error)")
            if playbackIntent {
                // Retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self = self, self.playbackIntent else { return }
                    print("[AudioEngine] Retrying after failure...")
                    self.createFreshPlayerItem()
                    self.player?.play()
                }
            } else {
                updateState(playing: false, buffering: false)
            }

        case .unknown:
            break

        @unknown default:
            break
        }
    }

    private func updateState(playing: Bool, buffering: Bool) {
        stateLock.withLock {
            _isPlaying = playing
            _isBuffering = buffering
        }
        onStateChanged?()
    }
}

// MARK: - Radio Player (Observable wrapper for SwiftUI)

@MainActor
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isLiveStream = true
    @Published private(set) var currentPlayingURL: URL?
    @Published var nowPlayingTitle = "Refuge Worldwide"
    @Published var nowPlayingSubtitle = ""
    @Published var nowPlayingArtworkURL: URL?

    private let engine = AudioEngine.shared
    private let soundCloudPlayer = SoundCloudPlayer.shared
    private var isSoundCloudPlaying = false

    private init() {
        // Listen to engine state changes
        engine.onStateChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isSoundCloudPlaying else { return }
                self.isPlaying = self.engine.isPlaying
                self.isBuffering = self.engine.isBuffering
                self.isLiveStream = self.engine.isLiveStream
                self.currentPlayingURL = self.engine.currentStreamURL
                self.updateNowPlayingPlaybackState()
            }
        }

        // Listen to SoundCloud player state changes
        soundCloudPlayer.onStateChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.isSoundCloudPlaying else { return }
                self.isPlaying = self.soundCloudPlayer.isPlaying
                self.isBuffering = self.soundCloudPlayer.isBuffering
                self.currentPlayingURL = self.soundCloudPlayer.currentURL
                self.updateNowPlayingPlaybackState()
            }
        }

        setupRemoteCommandCenter()
        setupInitialNowPlayingInfo()
    }

    // MARK: - Playback Control

    func play() {
        // Stop SoundCloud if playing
        if isSoundCloudPlaying {
            soundCloudPlayer.stop()
            isSoundCloudPlaying = false
        }

        engine.play()
        isPlaying = true
        isBuffering = true
        isLiveStream = true
        updateNowPlayingPlaybackState()
    }

    func playURL(_ url: URL, title: String? = nil, subtitle: String? = nil, artworkURL: URL? = nil) {
        // Update metadata first
        if let title = title {
            nowPlayingTitle = title
        }
        if let subtitle = subtitle {
            nowPlayingSubtitle = subtitle
        }
        if let artworkURL = artworkURL {
            nowPlayingArtworkURL = artworkURL
        }

        // Check if this is a SoundCloud URL
        if SoundCloudPlayer.isSoundCloudURL(url) {
            // Stop the audio engine if playing
            engine.stop()
            isSoundCloudPlaying = true
            soundCloudPlayer.play(url: url)
        } else {
            // Stop SoundCloud if playing
            if isSoundCloudPlaying {
                soundCloudPlayer.stop()
                isSoundCloudPlaying = false
            }
            engine.playURL(url)
        }

        isPlaying = true
        isBuffering = true
        isLiveStream = false
        currentPlayingURL = url
        updateNowPlayingInfo()
        updateNowPlayingPlaybackState()
    }

    func stop() {
        if isSoundCloudPlaying {
            soundCloudPlayer.stop()
            isSoundCloudPlaying = false
        } else {
            engine.stop()
        }

        isPlaying = false
        isBuffering = false
        currentPlayingURL = nil
        updateNowPlayingPlaybackState()
    }

    func toggle() {
        if isSoundCloudPlaying {
            if soundCloudPlayer.isPlaying {
                stop()
            } else {
                // Can't resume SoundCloud easily, just stop
                stop()
            }
        } else if engine.playbackIntent {
            stop()
        } else {
            play()
        }
    }

    /// Check if a specific URL is currently playing
    func isPlayingURL(_ url: URL) -> Bool {
        return isPlaying && currentPlayingURL == url
    }

    // MARK: - Now Playing Info

    private func setupInitialNowPlayingInfo() {
        updateNowPlayingInfo()
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }

        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }

        // Disable seek commands
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        print("[RadioPlayer] Remote command center configured")
    }

    func updateNowPlayingInfo(title: String? = nil, subtitle: String? = nil, artworkURL: URL? = nil) {
        if let title = title { nowPlayingTitle = title }
        if let subtitle = subtitle { nowPlayingSubtitle = subtitle }
        if let artworkURL = artworkURL { nowPlayingArtworkURL = artworkURL }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
        ]

        if !nowPlayingSubtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = nowPlayingSubtitle
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let url = nowPlayingArtworkURL {
            loadArtwork(from: url)
        }
    }

    private func updateNowPlayingPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyTitle] = nowPlayingTitle
        info[MPNowPlayingInfoPropertyIsLiveStream] = isLiveStream
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }

            // Crop to square for lock screen display
            let squareImage = image.croppedToSquare() ?? image

            Task { @MainActor in
                let size = CGSize(width: 600, height: 600)
                let artwork = MPMediaItemArtwork(boundsSize: size) { _ in squareImage }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }
}

// MARK: - UIImage Extension for Square Cropping

extension UIImage {
    func croppedToSquare() -> UIImage? {
        guard let cgImage = cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let sideLength = min(width, height)

        let origin = CGPoint(
            x: (width - sideLength) / 2,
            y: (height - sideLength) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: sideLength, height: sideLength))

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: imageOrientation)
    }
}
