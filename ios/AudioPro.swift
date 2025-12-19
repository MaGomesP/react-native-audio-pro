import Foundation
import AVFoundation
import React
import MediaPlayer
import UIKit

@objc(AudioPro)
class AudioPro: RCTEventEmitter {

	////////////////////////////////////////////////////////////
	// MARK: - Properties & Constants
	////////////////////////////////////////////////////////////

	private var player: AVPlayer?
	private var timer: Timer?
	private var hasListeners = false
	private let EVENT_NAME = "AudioProEvent"
	private let AMBIENT_EVENT_NAME = "AudioProAmbientEvent"
	private let QUEUE_EVENT_NAME = "AudioProQueueEvent"

	private var ambientPlayer: AVPlayer?
	private var ambientPlayerItem: AVPlayerItem?

	// Queue and Crossfade properties
	private var playerA: AVPlayer?
	private var playerB: AVPlayer?
	private var playerAItem: AVPlayerItem?
	private var playerBItem: AVPlayerItem?
	private var activePlayerIsA: Bool = true
	private var queue: [NSDictionary] = []
	private var currentQueueIndex: Int = 0
	private var queuePlaybackOptions: NSDictionary?
	private var crossfadeDurationMs: Double = 3000.0
	private var isCrossfading: Bool = false
	private var crossfadeTimer: Timer?
	private var isQueueMode: Bool = false
	private var isPlayerARateObserverAdded = false
	private var isPlayerBRateObserverAdded = false
	private var isPlayerAStatusObserverAdded = false
	private var isPlayerBStatusObserverAdded = false

	// Event types
	private let EVENT_TYPE_STATE_CHANGED = "STATE_CHANGED"
	private let EVENT_TYPE_TRACK_ENDED = "TRACK_ENDED"
	private let EVENT_TYPE_PLAYBACK_ERROR = "PLAYBACK_ERROR"
	private let EVENT_TYPE_PROGRESS = "PROGRESS"
	private let EVENT_TYPE_SEEK_COMPLETE = "SEEK_COMPLETE"
	private let EVENT_TYPE_REMOTE_NEXT = "REMOTE_NEXT"
	private let EVENT_TYPE_REMOTE_PREV = "REMOTE_PREV"
	private let EVENT_TYPE_PLAYBACK_SPEED_CHANGED = "PLAYBACK_SPEED_CHANGED"

	// Queue event types
	private let EVENT_TYPE_QUEUE_CHANGED = "QUEUE_CHANGED"
	private let EVENT_TYPE_QUEUE_ENDED = "QUEUE_ENDED"
	private let EVENT_TYPE_CROSSFADE_STARTED = "CROSSFADE_STARTED"
	private let EVENT_TYPE_CROSSFADE_COMPLETED = "CROSSFADE_COMPLETED"
	private let EVENT_TYPE_QUEUE_TRACK_CHANGED = "QUEUE_TRACK_CHANGED"

	// Seek trigger sources
	private let TRIGGER_SOURCE_USER = "USER"
	private let TRIGGER_SOURCE_SYSTEM = "SYSTEM"

	// Ambient audio event types
	private let EVENT_TYPE_AMBIENT_TRACK_ENDED = "AMBIENT_TRACK_ENDED"
	private let EVENT_TYPE_AMBIENT_ERROR = "AMBIENT_ERROR"

	// States
	private let STATE_IDLE = "IDLE"
	private let STATE_STOPPED = "STOPPED"
	private let STATE_LOADING = "LOADING"
	private let STATE_PLAYING = "PLAYING"
	private let STATE_PAUSED = "PAUSED"
	private let STATE_ERROR = "ERROR"

	private let GENERIC_ERROR_CODE = 900
	private var shouldBePlaying = false
	private var isRemoteCommandCenterSetup = false

	private var isRateObserverAdded = false
	private var isStatusObserverAdded = false

	private var currentPlaybackSpeed: Float = 1.0
	private var currentTrack: NSDictionary?

	private var settingDebug: Bool = false
	private var settingDebugIncludeProgress: Bool = false
	private var settingProgressInterval: TimeInterval = 1.0
	private var settingShowNextPrevControls = true
	private var settingShowSkipControls = false
	private var settingLoopAmbient: Bool = true

	private var activeVolume: Float = 1.0
	private var activeVolumeAmbient: Float = 1.0

	private var isInErrorState: Bool = false
	private var lastEmittedState: String = ""
	private var wasPlayingBeforeInterruption: Bool = false
	private var pendingStartTimeMs: Double? = nil
	private var settingSkipIntervalMs: Double = 30000.0

	////////////////////////////////////////////////////////////
	// MARK: - React Native Event Emitter Overrides
	////////////////////////////////////////////////////////////

	override func supportedEvents() -> [String]! {
		return [EVENT_NAME, AMBIENT_EVENT_NAME, QUEUE_EVENT_NAME]
	}

	override static func requiresMainQueueSetup() -> Bool {
		return false
	}

	override func startObserving() {
		hasListeners = true
	}

	override func stopObserving() {
		hasListeners = false
	}

	private func setupAudioSessionInterruptionObserver() {
		// Register for audio session interruption notifications
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAudioSessionInterruption(_:)),
			name: AVAudioSession.interruptionNotification,
			object: nil
		)

		log("Registered for audio session interruption notifications")
	}

	private func removeAudioSessionInterruptionObserver() {
		NotificationCenter.default.removeObserver(
			self,
			name: AVAudioSession.interruptionNotification,
			object: nil
		)
	}

	@objc private func handleAudioSessionInterruption(_ notification: Notification) {
		guard let userInfo = notification.userInfo,
			  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
			  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
			return
		}

		log("Audio session interruption: \(type)")

		switch type {
		case .began:
			// Interruption began (e.g., phone call, Siri, other app playing audio)
			wasPlayingBeforeInterruption = player?.rate != 0
			log("wasPlayingBeforeInterruption set to", wasPlayingBeforeInterruption)

			if wasPlayingBeforeInterruption {
				log("Interruption began while playing, pausing playback")
				// Pause playback without changing shouldBePlaying flag
				player?.pause()
				stopTimer()

				// Emit PAUSED state to ensure UI is in sync
				sendPausedStateEvent()

				// Update now playing info to show paused state
				updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0)
			}

		case .ended:
			// Interruption ended
			guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
				return
			}

			let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

			log("wasPlayingBeforeInterruption at end:", wasPlayingBeforeInterruption)
			log("shouldResume:", options.contains(.shouldResume))

			// If playback should resume and we have permission to do so
			if wasPlayingBeforeInterruption && options.contains(.shouldResume) {
				log("Interruption ended with resume option, resuming playback")

				// Try to reactivate the audio session
				do {
					try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

					// Resume playback
					player?.play()
					startProgressTimer()

					// Emit PLAYING state
					sendPlayingStateEvent()

					// Update now playing info
					updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 1.0)
				} catch {
					log("Failed to reactivate audio session: \(error.localizedDescription)")
					emitPlaybackError("Failed to resume after interruption: \(error.localizedDescription)")
				}
			}

			// Reset the flag
			wasPlayingBeforeInterruption = false
		@unknown default:
			break
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Debug Logging Helper
	////////////////////////////////////////////////////////////

	private func log(_ items: Any...) {
		guard settingDebug else { return }

		if !settingDebugIncludeProgress && items.count > 0 {
			if let firstItem = items.first, "\(firstItem)" == EVENT_TYPE_PROGRESS {
				return
			}
		}

		print("~~~ [AudioPro]", items.map { "\($0)" }.joined(separator: " "))
	}

	private func sendEvent(type: String, track: Any?, payload: [String: Any]?) {
		guard hasListeners else { return }

		var body: [String: Any] = [
			"type": type,
			"track": track as Any
		]

		if let payload = payload {
			body["payload"] = payload
		}

		log(type)

		sendEvent(withName: EVENT_NAME, body: body)
	}


	////////////////////////////////////////////////////////////
	// MARK: - Timers & Progress Updates
	////////////////////////////////////////////////////////////

	private func startProgressTimer() {
		DispatchQueue.main.async {
			self.timer?.invalidate()
			self.sendProgressNoticeEvent()
			self.timer = Timer.scheduledTimer(withTimeInterval: self.settingProgressInterval, repeats: true) { [weak self] _ in
				self?.sendProgressNoticeEvent()
			}
		}
	}

	private func stopTimer() {
		DispatchQueue.main.async {
			self.timer?.invalidate()
			self.timer = nil
		}
	}

	private func sendProgressNoticeEvent() {
		// Check if we're in queue mode
		if isQueueMode {
			sendQueueProgressNoticeEvent()
			return
		}

		guard let player = player, let _ = player.currentItem, player.rate != 0 else { return }
		let info = getPlaybackInfo()

		let payload: [String: Any] = [
			"position": info.position,
			"duration": info.duration
		]
		sendEvent(type: EVENT_TYPE_PROGRESS, track: info.track, payload: payload)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Playback Control (Play, Pause, Resume, Stop)
	////////////////////////////////////////////////////////////

	/// Prepares the player for new playback without emitting state changes or destroying the media session
	/// - This function:
	/// - Pauses the player if it's playing
	/// - Removes KVO observers from the previous AVPlayerItem
	/// - Stops the progress timer
	/// - Does not emit any state or clear currentTrack
	/// - Does not destroy the media session
	private func prepareForNewPlayback() {
		// Pause the player if it's playing
		player?.pause()

		// Stop the progress timer
		stopTimer()

		// Remove KVO observers from the previous AVPlayerItem
		if let player = player {
			if isRateObserverAdded {
				player.removeObserver(self, forKeyPath: "rate")
				isRateObserverAdded = false
			}
			if let currentItem = player.currentItem, isStatusObserverAdded {
				currentItem.removeObserver(self, forKeyPath: "status")
				isStatusObserverAdded = false
			}
		}

		// Remove playback ended notification observer
		NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
	}

	@objc(play:withOptions:)
	func play(track: NSDictionary, options: NSDictionary) {
		// Reset error state when playing a new track
		isInErrorState = false
		// Reset last emitted state when playing a new track
		lastEmittedState = ""
		currentTrack = track
		settingDebug = options["debug"] as? Bool ?? false
		settingDebugIncludeProgress = options["debugIncludesProgress"] as? Bool ?? false
		let speed = Float(options["playbackSpeed"] as? Double ?? 1.0)
		let volume = Float(options["volume"] as? Double ?? 1.0)
		let autoPlay = options["autoPlay"] as? Bool ?? true
		settingShowNextPrevControls = options["showNextPrevControls"] as? Bool ?? true
		settingShowSkipControls = options["showSkipControls"] as? Bool ?? false
		pendingStartTimeMs = options["startTimeMs"] as? Double

		if let skipIntervalMs = options["skipIntervalMs"] as? Double {
			settingSkipIntervalMs = skipIntervalMs
			log("Skip interval set to", settingSkipIntervalMs, "milliseconds")
		}

		if let progressIntervalMs = options["progressIntervalMs"] as? Double {
			let intervalSeconds = progressIntervalMs / 1000.0
			settingProgressInterval = intervalSeconds
		} else {
			settingProgressInterval = 1.0
		}

		currentPlaybackSpeed = speed
		activeVolume = volume
		log("Play", track["title"] ?? "Unknown", "speed:", speed, "volume:", volume, "autoPlay:", autoPlay)

		if player != nil {
			DispatchQueue.main.sync {
				// Prepare for new playback without emitting state changes or destroying the media session
				prepareForNewPlayback()
			}
		}

		guard
			let urlString = track["url"] as? String,
			let url = URL(string: urlString),
			let title = track["title"] as? String,
			let artworkUrlString = track["artwork"] as? String,
			let artworkUrl = URL(string: artworkUrlString)
		else {
			onError("Invalid track data")
			cleanup()
			return
		}

		do {
			let contentType = options["contentType"] as? String ?? "MUSIC"
			let mode: AVAudioSession.Mode = (contentType == "SPEECH") ? .spokenAudio : .default
			try AVAudioSession.sharedInstance().setCategory(.playback, mode: mode)
			try AVAudioSession.sharedInstance().setActive(true)

			// Set up audio session interruption observer
			setupAudioSessionInterruptionObserver()
		} catch {
			onError("Audio session setup failed: \(error.localizedDescription)")
			return
		}

		sendStateEvent(state: STATE_LOADING, position: 0, duration: 0, track: currentTrack)
		shouldBePlaying = autoPlay

		let album = track["album"] as? String
		let artist = track["artist"] as? String

		// Update now playing info without resetting the entire dictionary
		var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
		nowPlayingInfo[MPMediaItemPropertyTitle] = title
		if let album = album {
			nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
		}
		if let artist = artist {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artist
		}
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

		// Set up remote transport controls only if they haven't been set up yet
		DispatchQueue.main.async {
			if !self.isRemoteCommandCenterSetup {
				UIApplication.shared.beginReceivingRemoteControlEvents()
				self.setupRemoteTransportControls()
			}
		}

		// Create new player item with custom headers if provided
		let item: AVPlayerItem

		// Check if audio headers are provided
		if let headers = options["headers"] as? NSDictionary, let audioHeaders = headers["audio"] as? NSDictionary {
			// Convert headers to Swift dictionary
			var headerFields = [String: String]()
			for (key, value) in audioHeaders {
				if let headerField = key as? String, let headerValue = value as? String {
					headerFields[headerField] = headerValue
				}
			}

			// Create an AVAsset with the headers
			let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headerFields])
			item = AVPlayerItem(asset: asset)
		} else {
			// No headers, use simple URL initialization
			item = AVPlayerItem(url: url)
		}

		// Add observer to the new item
		item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
		isStatusObserverAdded = true

		// Create the AVPlayer if it doesn't exist, otherwise just replace the item
		if player == nil {
			// Create a new AVPlayer instance
			player = AVPlayer(playerItem: item)
		} else {
			// Replace the current item with the new one
			player?.replaceCurrentItem(with: item)
		}

		// Add rate observer to the player
		player?.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
		isRateObserverAdded = true

		// Set up volume to ensure it's applied before playback starts
		player?.volume = activeVolume

		nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
		nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
		nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = item.asset.duration.seconds
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

		// Add notification observer for track completion to the new item
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(playerItemDidPlayToEndTime(_:)),
			name: .AVPlayerItemDidPlayToEndTime,
			object: item
		)

		// Set up playback speed
		if currentPlaybackSpeed != 1.0 {
			player?.rate = currentPlaybackSpeed

			var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
			currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = Double(currentPlaybackSpeed)
			MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
		}

		if autoPlay {
			player?.play()
		} else {
			DispatchQueue.main.async {
				self.sendStateEvent(state: self.STATE_PAUSED, position: 0, duration: 0, track: self.currentTrack)
			}
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			// Don't emit PLAYING state if we're in an error state
			if self.isInErrorState {
				self.log("Ignoring delayed PLAYING state after ERROR")
				return
			}

			if self.player?.rate != 0 && self.hasListeners {
				// Use sendPlayingStateEvent to ensure lastEmittedState is updated
				self.sendPlayingStateEvent()
				self.startProgressTimer()
			}
		}

		// Fetch artwork asynchronously and update Now Playing info
		DispatchQueue.global().async {
			do {
				// Check if artwork headers are provided
				if let headers = options["headers"] as? NSDictionary, let artworkHeaders = headers["artwork"] as? NSDictionary {
					// Create a simple URL request with headers
					var request = URLRequest(url: artworkUrl)
					for (key, value) in artworkHeaders {
						if let headerField = key as? String, let headerValue = value as? String {
							request.setValue(headerValue, forHTTPHeaderField: headerField)
						}
					}

					// Use a semaphore to make the async call synchronous in this background thread
					let semaphore = DispatchSemaphore(value: 0)
					var imageData: Data? = nil
					var requestError: Error? = nil

					URLSession.shared.dataTask(with: request) { (data, response, error) in
						imageData = data
						requestError = error
						semaphore.signal()
					}.resume()

					// Wait for the request to complete
					semaphore.wait()

					if let error = requestError {
						throw error
					}

					guard let data = imageData else {
						throw NSError(domain: "AudioPro", code: 0, userInfo: [NSLocalizedDescriptionKey: "No image data received"])
					}

					guard let image = UIImage(data: data) else {
						throw NSError(domain: "AudioPro", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
					}

					let mpmArtwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
					DispatchQueue.main.async {
						var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
						currentInfo[MPMediaItemPropertyArtwork] = mpmArtwork
						MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
					}
				} else {
					// No headers, use simple Data initialization
					let data = try Data(contentsOf: artworkUrl)
					guard let image = UIImage(data: data) else {
						throw NSError(domain: "AudioPro", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
					}
					let mpmArtwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
					DispatchQueue.main.async {
						var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
						currentInfo[MPMediaItemPropertyArtwork] = mpmArtwork
						MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
					}
				}
			} catch {
				DispatchQueue.main.async {
					self.onError(error.localizedDescription)
					self.cleanup()
				}
			}
		}
	}

	@objc(pause)
	func pause() {
		shouldBePlaying = false

		// Handle queue mode
		if isQueueMode {
			getActivePlayer()?.pause()
			// Also pause inactive player if crossfading
			if isCrossfading {
				getInactivePlayer()?.pause()
			}
			updateNowPlayingInfo(time: getActivePlayer()?.currentTime().seconds ?? 0, rate: 0)
		} else {
			player?.pause()
			updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0)
		}

		stopTimer()
		sendPausedStateEvent()
	}

	@objc(resume)
	func resume() {
		shouldBePlaying = true

		// Try to reactivate the audio session if needed
		do {
			if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
				try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
			}
		} catch {
			log("Failed to reactivate audio session: \(error.localizedDescription)")
			// Continue anyway, as the play command might still work
		}

		// Handle queue mode
		if isQueueMode {
			getActivePlayer()?.play()
			// Also resume inactive player if crossfading
			if isCrossfading {
				getInactivePlayer()?.play()
			}
			// Apply playback speed
			if currentPlaybackSpeed != 1.0 {
				getActivePlayer()?.rate = currentPlaybackSpeed
				if isCrossfading {
					getInactivePlayer()?.rate = currentPlaybackSpeed
				}
			}
			updateNowPlayingInfo(time: getActivePlayer()?.currentTime().seconds ?? 0, rate: 1.0)
		} else {
			player?.play()
			updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 1.0)
		}

		// Note: We don't need to call sendPlayingStateEvent() here because
		// the rate change will trigger observeValue which now calls sendPlayingStateEvent()
	}

	/// stop is meant to halt playback and update the state without destroying persistent info
	/// such as artwork and remote control settings. This allows the lock screen/Control Center
	/// to continue displaying the track details for a potential resume.
	@objc func stop() {
		// Reset error state when explicitly stopping
		isInErrorState = false
		// Reset last emitted state when stopping playback
		lastEmittedState = ""
		shouldBePlaying = false

		pendingStartTimeMs = nil

		// Handle queue mode
		if isQueueMode {
			// Stop crossfade if in progress
			crossfadeTimer?.invalidate()
			crossfadeTimer = nil
			isCrossfading = false

			// Stop both queue players
			getActivePlayer()?.pause()
			getActivePlayer()?.seek(to: .zero)
			getInactivePlayer()?.pause()
			getInactivePlayer()?.seek(to: .zero)
		} else {
			// Stop single player
			player?.pause()
			player?.seek(to: .zero)
		}

		stopTimer()
		// Do not set currentTrack = nil as STOPPED state should preserve track metadata
		sendStoppedStateEvent()

		// Update now playing info to reflect a stopped state but keep the artwork intact.
		updateNowPlayingInfo(time: 0, rate: 0)
	}

	/// Resets the player to IDLE state, fully tears down the player instance,
	/// and removes all media sessions.
	@objc(clear)
	func clear() {
		log("Clear called")
		resetInternal(STATE_IDLE)
	}

	/// Shared internal function that performs the teardown and emits the correct state.
	/// Used by both clear() and error transitions.
	/// - Parameter finalState: The state to emit after resetting (IDLE or ERROR)
	private func resetInternal(_ finalState: String) {
		// Reset error state
		isInErrorState = finalState == STATE_ERROR
		// Reset last emitted state
		lastEmittedState = ""
		shouldBePlaying = false

		// Reset volume to default
		activeVolume = 1.0

		pendingStartTimeMs = nil

		// Reset queue state to ensure clean transition back to single-track mode
		if isQueueMode {
			cleanupQueuePlayers()
		}
		isQueueMode = false
		queue = []
		currentQueueIndex = 0
		isCrossfading = false
		crossfadeTimer?.invalidate()
		crossfadeTimer = nil
		queuePlaybackOptions = nil

		// Stop playback
		player?.pause()

		// Clear track and stop timers
		stopTimer()
		currentTrack = nil

		// Release resources and remove observers
		// We've already cleared currentTrack, so we don't need to do it again in cleanup
		cleanup(emitStateChange: false, clearTrack: false)

		// Emit the final state
		// Explicitly pass nil as the track parameter to ensure the state is emitted consistently
		sendStateEvent(state: finalState, position: 0, duration: 0, track: nil)
	}

	/// cleanup fully tears down the player instance and removes observers and remote controls.
	/// This is used when switching tracks or recovering from an error.
	/// - Parameter emitStateChange: Whether to emit a STOPPED state change event (default: true)
	/// - Parameter clearTrack: Whether to clear the currentTrack (default: true)
	@objc func cleanup(emitStateChange: Bool = true, clearTrack: Bool = true) {
		log("Cleanup", "emitStateChange:", emitStateChange, "clearTrack:", clearTrack)

		// Reset pending start time
		pendingStartTimeMs = nil

		shouldBePlaying = false

		NotificationCenter.default.removeObserver(self)

		// Explicitly remove audio session interruption observer
		removeAudioSessionInterruptionObserver()

		if let player = player {
			if isRateObserverAdded {
				player.removeObserver(self, forKeyPath: "rate")
				isRateObserverAdded = false
			}
			if let currentItem = player.currentItem, isStatusObserverAdded {
				currentItem.removeObserver(self, forKeyPath: "status")
				isStatusObserverAdded = false
			}
		}

		player?.pause()
		player = nil

		stopTimer()

		// Only clear the track if requested
		if clearTrack {
			currentTrack = nil
		}

		// Only emit state change if requested and not in error state
		if emitStateChange && !isInErrorState {
			sendStoppedStateEvent()
		}

		// Clear the now playing info and remote control events
		DispatchQueue.main.async {
			MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
			UIApplication.shared.endReceivingRemoteControlEvents()
			self.removeRemoteTransportControls()
			self.isRemoteCommandCenterSetup = false
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Seeking Methods
	////////////////////////////////////////////////////////////

	/// Common seek implementation used by all seek methods
	private func performSeek(to position: Double, isAbsolute: Bool = true) {
		// Get the appropriate player based on mode
		let targetPlayer: AVPlayer?
		if isQueueMode {
			targetPlayer = getActivePlayer()
		} else {
			targetPlayer = player
		}

		guard let player = targetPlayer else {
			log("Cannot seek: no track is playing")
			return
		}

		guard let currentItem = player.currentItem else {
			log("Cannot seek: no item loaded")
			return
		}

		let duration = currentItem.duration.seconds
		let currentTime = player.currentTime().seconds

		// For relative seeking (forward/back), we need valid current time
		if !isAbsolute && (currentTime.isNaN || currentTime.isInfinite) {
			log("Cannot seek: invalid track position")
			return
		}

		// For all seeks, we need valid duration
		if duration.isNaN || duration.isInfinite {
			log("Cannot seek: invalid track duration")
			return
		}

		stopTimer()

		// Calculate target position based on whether this is absolute or relative
		let targetPosition: Double
		if isAbsolute {
			// For seekTo, convert ms to seconds
			targetPosition = position / 1000.0
		} else {
			// For seekForward/Back, position is the amount in ms
			let amountInSeconds = position / 1000.0
			targetPosition = isAbsolute ? amountInSeconds :
							 (position >= 0) ? min(currentTime + amountInSeconds, duration) :
											  max(0, currentTime + amountInSeconds)
		}

		// Ensure position is within valid range
		let validPosition = max(0, min(targetPosition, duration))
		let time = CMTime(seconds: validPosition, preferredTimescale: 1000)

		player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
			guard let self = self else { return }
			if completed {
				self.updateNowPlayingInfoWithCurrentTime(validPosition)
				self.completeSeekingAndSendSeekCompleteNoticeEvent(newPosition: validPosition * 1000)

				// Force update the now playing info to ensure controls work
				if isAbsolute { // Only do this for absolute seeks to avoid redundant updates
					DispatchQueue.main.async {
						var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
						info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validPosition
						info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
						MPNowPlayingInfoCenter.default().nowPlayingInfo = info
					}
				}
			} else if player.rate != 0 {
				self.startProgressTimer()
			}
		}
	}

	@objc(seekTo:)
	func seekTo(position: Double) {
		performSeek(to: position, isAbsolute: true)
	}

	@objc(seekForward:)
	func seekForward(amount: Double) {
		performSeek(to: amount, isAbsolute: false)
	}

	@objc(seekBack:)
	func seekBack(amount: Double) {
		performSeek(to: -amount, isAbsolute: false)
	}


	private func completeSeekingAndSendSeekCompleteNoticeEvent(newPosition: Double) {
		if hasListeners {
			let info = getPlaybackInfo()

			let payload: [String: Any] = [
				"position": info.position,
				"duration": info.duration,
				"triggeredBy": TRIGGER_SOURCE_USER
			]
			sendEvent(type: EVENT_TYPE_SEEK_COMPLETE, track: info.track, payload: payload)
		}
		if player?.rate != 0 {
			// Resume progress timer after a short delay to ensure UI is in sync
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
				self.startProgressTimer()
			}
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Playback Speed
	////////////////////////////////////////////////////////////

	@objc(setPlaybackSpeed:)
	func setPlaybackSpeed(speed: Double) {
		currentPlaybackSpeed = Float(speed)

		guard let player = player else {
			onError("Cannot set playback speed: no track is playing")
			return
		}

		log("Setting playback speed to ", speed)
		player.rate = Float(speed)

		updateNowPlayingInfo(rate: Float(speed))

		if hasListeners {
			let playbackInfo = getPlaybackInfo()
			let payload: [String: Any] = ["speed": speed]
			sendEvent(type: EVENT_TYPE_PLAYBACK_SPEED_CHANGED, track: playbackInfo.track, payload: payload)
		}
	}

	@objc(setVolume:)
	func setVolume(volume: Double) {
		activeVolume = Float(volume)

		guard let player = player else {
			log("Cannot set volume: no track is playing")
			return
		}

		log("Setting volume to ", volume)
		player.volume = Float(volume)
	}

	////////////////////////////////////////////////////////////
	// MARK: - KVO & Notification Handlers
	////////////////////////////////////////////////////////////

	/**
	 * Handles track completion according to the contract in logic.md:
	 * - Native is responsible for detecting the end of a track
	 * - Native must pause the player, seek to position 0, and emit both:
	 *   - STATE_CHANGED: STOPPED
	 *   - TRACK_ENDED
	 */
	@objc private func playerItemDidPlayToEndTime(_ notification: Notification) {
		guard let _ = player?.currentItem else { return }

		if isInErrorState {
			log("Ignoring track end notification while in ERROR state")
			return
		}

		let info = getPlaybackInfo()

		isInErrorState = false
		lastEmittedState = ""
		shouldBePlaying = false

		player?.seek(to: .zero)
		stopTimer()

		updateNowPlayingInfo(time: 0, rate: 0)

		sendStateEvent(state: STATE_STOPPED, position: 0, duration: info.duration, track: currentTrack)

		if hasListeners {
			let payload: [String: Any] = [
				"position": info.duration,
				"duration": info.duration
			]
			sendEvent(type: EVENT_TYPE_TRACK_ENDED, track: currentTrack, payload: payload)
		}
	}

	override func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change: [NSKeyValueChangeKey: Any]?,
		context: UnsafeMutableRawPointer?
	) {
		// Guard against state changes while in error state
		guard !isInErrorState else {
			log("Ignoring state change while in ERROR state")
			return
		}

		guard let keyPath = keyPath else { return }

		switch keyPath {
		case "status":
			if let item = object as? AVPlayerItem {
				switch item.status {
				case .readyToPlay:
					log("Player item ready to play")
					if let pendingStartTimeMs = pendingStartTimeMs {
						performSeek(to: pendingStartTimeMs, isAbsolute: true)
						self.pendingStartTimeMs = nil
					}
				case .failed:
					// In queue mode, check if this is the active player's item or the inactive (pre-buffering) player's item
					if isQueueMode {
						let activePlayerItem = activePlayerIsA ? playerAItem : playerBItem
						let isActivePlayerItem = (item === activePlayerItem)

						if isActivePlayerItem {
							// Active player failed - this is a real error
							let errorMessage = item.error?.localizedDescription ?? "Unknown error"
							log("Queue active player item failed:", errorMessage)
							emitPlaybackError("Player item failed: \(errorMessage)")
							// Try to skip to next track instead of crashing everything
							if currentQueueIndex + 1 < queue.count {
								log("Attempting to skip to next track after error")
								skipToNextInternal(withCrossfade: false)
							} else {
								// No more tracks, end the queue
								shouldBePlaying = false
								stopTimer()
								sendStateEvent(state: STATE_STOPPED, position: 0, duration: 0, track: currentTrack)
								sendQueueEvent(type: EVENT_TYPE_QUEUE_ENDED, payload: buildQueueInfoPayload())
							}
						} else {
							// Inactive (pre-buffering) player failed - just log it, don't crash the current playback
							let errorMessage = item.error?.localizedDescription ?? "Unknown error"
							log("Queue pre-buffer player item failed (non-fatal):", errorMessage)
							// We can emit a soft error event but don't stop playback
							emitPlaybackError("Failed to pre-buffer next track: \(errorMessage)")
						}
					} else {
						// Not in queue mode - use original error handling
						if let error = item.error {
							onError("Player item failed: \(error.localizedDescription)")
						} else {
							onError("Player item failed with unknown error")
						}
					}
				case .unknown:
					break
				@unknown default:
					break
				}
			}
		case "rate":
			if let newRate = change?[.newKey] as? Float {
				// In queue mode, only respond to rate changes from the active player
				if isQueueMode {
					let activePlayer = getActivePlayer()
					let rateChangedPlayer = object as? AVPlayer

					// Only handle rate changes from the active player
					if rateChangedPlayer !== activePlayer {
						log("Ignoring rate change from inactive queue player")
						return
					}

					if newRate == 0 {
						if shouldBePlaying && hasListeners && !isCrossfading {
							let info = getQueuePlaybackInfo()
							sendStateEvent(state: STATE_LOADING, position: info.position, duration: info.duration, track: info.track)
							stopTimer()
						}
					} else {
						if shouldBePlaying && hasListeners && !isCrossfading {
							sendPlayingStateEvent()
							startProgressTimer()
						}
					}
				} else {
					// Original single-player mode handling
					if newRate == 0 {
						if shouldBePlaying && hasListeners {
							let info = getPlaybackInfo()
							sendStateEvent(state: STATE_LOADING, position: info.position, duration: info.duration, track: info.track)
							stopTimer()
						}
					} else {
						if shouldBePlaying && hasListeners {
							// Use sendPlayingStateEvent to ensure lastEmittedState is updated
							sendPlayingStateEvent()
							startProgressTimer()
						}
					}
				}
			}
		default:
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Private Helpers & Error Handling
	////////////////////////////////////////////////////////////

	private func getPlaybackInfo() -> (position: Int, duration: Int, track: NSDictionary?) {
		guard let player = player, let currentItem = player.currentItem else {
			return (0, 0, currentTrack)
		}
		let currentTimeSec = player.currentTime().seconds
		let durationSec = currentItem.duration.seconds
		let validCurrentTimeSec = (currentTimeSec.isNaN || currentTimeSec.isInfinite) ? 0 : currentTimeSec
		let validDurationSec = (durationSec.isNaN || durationSec.isInfinite) ? 0 : durationSec

		// Calculate position and duration in milliseconds
		let positionMs = Int(round(validCurrentTimeSec * 1000))
		let durationMs = Int(round(validDurationSec * 1000))

		// Sanitize negative values
		let sanitizedPositionMs = positionMs < 0 ? 0 : positionMs
		let sanitizedDurationMs = durationMs < 0 ? 0 : durationMs

		return (position: sanitizedPositionMs, duration: sanitizedDurationMs, track: currentTrack)
	}

	private func sendStateEvent(state: String, position: Int? = nil, duration: Int? = nil, track: NSDictionary? = nil) {
		guard hasListeners else { return }

		// When in error state, only allow ERROR or IDLE states to be emitted
		// IDLE is allowed because clear() should reset the player regardless of previous state
		if isInErrorState && state != STATE_ERROR && state != STATE_IDLE {
			log("Ignoring \(state) state after ERROR")
			return
		}

		// Filter out duplicate state emissions
		// This prevents rapid-fire transitions of the same state being emitted repeatedly
		if state == lastEmittedState {
			log("Ignoring duplicate \(state) state emission")
			return
		}

		// Use provided values or get from getPlaybackInfo() which already sanitizes values
		let info = position == nil || duration == nil ? getPlaybackInfo() : (position: position!, duration: duration!, track: track)

		let payload: [String: Any] = [
			"state": state,
			"position": info.position,
			"duration": info.duration
		]
		sendEvent(type: EVENT_TYPE_STATE_CHANGED, track: info.track ?? track, payload: payload)

		// Track the last emitted state
		lastEmittedState = state
	}

	private func sendStoppedStateEvent() {
		sendStateEvent(state: STATE_STOPPED, position: 0, duration: 0, track: currentTrack)
	}

	private func sendPlayingStateEvent() {
		sendStateEvent(state: STATE_PLAYING, track: currentTrack)
	}

	private func sendPausedStateEvent() {
		sendStateEvent(state: STATE_PAUSED, track: currentTrack)
	}

	/// Stops playback without emitting a state change event
	/// Used for error handling to avoid emitting STOPPED after ERROR
	private func stopPlaybackWithoutStateChange() {
		// Use the cleanup method with emitStateChange set to false
		cleanup(emitStateChange: false)
	}

	/// Updates Now Playing Info with specified parameters, preserving existing values
	private func updateNowPlayingInfo(time: Double? = nil, rate: Float? = nil, duration: Double? = nil, track: NSDictionary? = nil) {
		var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

		// Update time if provided
		if let time = time {
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
		}

		// Update rate if provided, otherwise use current player rate
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate ?? player?.rate ?? 0

		// Update duration if provided, otherwise try to get from current item
		if let duration = duration {
			nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
		} else if let currentItem = player?.currentItem {
			let itemDuration = currentItem.duration.seconds
			if !itemDuration.isNaN && !itemDuration.isInfinite {
				nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = itemDuration
			}
		}

		// Ensure we have the basic track info from either provided track or current track
		let trackInfo = track ?? currentTrack
		if let trackInfo = trackInfo {
			if nowPlayingInfo[MPMediaItemPropertyTitle] == nil, let title = trackInfo["title"] as? String {
				nowPlayingInfo[MPMediaItemPropertyTitle] = title
			}
			if nowPlayingInfo[MPMediaItemPropertyArtist] == nil, let artist = trackInfo["artist"] as? String {
				nowPlayingInfo[MPMediaItemPropertyArtist] = artist
			}
			if nowPlayingInfo[MPMediaItemPropertyAlbumTitle] == nil, let album = trackInfo["album"] as? String {
				nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
			}
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}

	private func updateNowPlayingInfoWithCurrentTime(_ time: Double) {
		updateNowPlayingInfo(time: time)
	}

	/**
	 * Emits a PLAYBACK_ERROR event without transitioning to the ERROR state.
	 * Use this for non-critical errors that don't require player teardown.
	 *
	 * According to the contract in logic.md:
	 * - PLAYBACK_ERROR and ERROR state are separate and must not be conflated
	 * - PLAYBACK_ERROR can be emitted with or without a corresponding state change
	 * - Useful for soft errors (e.g., image fetch failed, headers issue, non-fatal network retry)
	 */
	func emitPlaybackError(_ errorMessage: String, code: Int = 900) {
		if hasListeners {
			let errorPayload: [String: Any] = [
				"error": errorMessage,
				"errorCode": code
			]
			sendEvent(type: EVENT_TYPE_PLAYBACK_ERROR, track: currentTrack, payload: errorPayload)
		}
	}

	/**
	 * Handles critical errors according to the contract in logic.md:
	 * - onError() should transition to ERROR state
	 * - onError() should emit STATE_CHANGED: ERROR and PLAYBACK_ERROR
	 * - onError() should clear the player state just like clear()
	 *
	 * This method is for unrecoverable player failures that require player teardown.
	 * For non-critical errors that don't require state transition, use emitPlaybackError() instead.
	 */
	func onError(_ errorMessage: String) {
		// If we're already in an error state, just log and return
		if isInErrorState {
			log("Already in error state, ignoring additional error: \(errorMessage)")
			return
		}

		if hasListeners {
			// First, emit PLAYBACK_ERROR event with error details
			let errorPayload: [String: Any] = [
				"error": errorMessage,
				"errorCode": GENERIC_ERROR_CODE
			]
			sendEvent(type: EVENT_TYPE_PLAYBACK_ERROR, track: currentTrack, payload: errorPayload)
		}

		// Then use the shared resetInternal function to:
		// 1. Clear the player state (like clear())
		// 2. Emit STATE_CHANGED: ERROR
		resetInternal(STATE_ERROR)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Remote Control Commands & Magic Tap Support
	////////////////////////////////////////////////////////////

	private func setupRemoteTransportControls() {
		if isRemoteCommandCenterSetup { return }
		let commandCenter = MPRemoteCommandCenter.shared()

		// Remove both controls first (reset state)
		commandCenter.nextTrackCommand.isEnabled = false
		commandCenter.previousTrackCommand.isEnabled = false
		commandCenter.skipForwardCommand.isEnabled = false
		commandCenter.skipBackwardCommand.isEnabled = false

		if settingShowNextPrevControls {
			// Enable next/prev, skip stays disabled
			commandCenter.nextTrackCommand.isEnabled = true
			commandCenter.previousTrackCommand.isEnabled = true
		} else if settingShowSkipControls {
			// Enable skip only if next/prev are NOT shown
			commandCenter.skipForwardCommand.isEnabled = true
			commandCenter.skipBackwardCommand.isEnabled = true
		}

		// Always enable play, pause, toggle, and changePlaybackPosition commands
		commandCenter.playCommand.isEnabled = true
		commandCenter.pauseCommand.isEnabled = true
		commandCenter.togglePlayPauseCommand.isEnabled = true
		commandCenter.changePlaybackPositionCommand.isEnabled = true

		// Register command targets as before (disabling just hides/prevents UI, targets are safe to always register)
		commandCenter.skipForwardCommand.addTarget { [weak self] event in
			guard let self = self else { return .commandFailed }
			self.seekForward(amount: self.settingSkipIntervalMs)
			return .success
		}

		commandCenter.skipBackwardCommand.addTarget { [weak self] event in
			guard let self = self else { return .commandFailed }
			self.seekBack(amount: self.settingSkipIntervalMs)
			return .success
		}

		commandCenter.playCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.player?.rate == 0 {
				self.resume()
				return .success
			}
			return .commandFailed
		}

		commandCenter.pauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.player?.rate != 0 {
				self.pause()
				return .success
			}
			return .commandFailed
		}

		// Magic Tap Support: Toggle Play/Pause command
		// This enables VoiceOver Magic Tap (two-finger double-tap) functionality
		commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
			guard let self = self, let player = self.player else { return .commandFailed }

			self.log("Magic Tap (togglePlayPause) triggered")

			if player.rate > 0 {
				// Currently playing → pause
				self.pause()
				self.log("Magic Tap: Paused")
				return .success
			} else if self.currentTrack != nil {
				// Has track but paused → resume
				self.resume()
				self.log("Magic Tap: Resumed")
				return .success
			}

			return .commandFailed
		}

		commandCenter.nextTrackCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.sendEvent(type: self.EVENT_TYPE_REMOTE_NEXT, track: self.currentTrack, payload: ["state": self.lastEmittedState])
			return .success
		}

		commandCenter.previousTrackCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.sendEvent(type: self.EVENT_TYPE_REMOTE_PREV, track: self.currentTrack, payload: ["state": self.lastEmittedState])
			return .success
		}

		commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
			guard let self = self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
				return .commandFailed
			}
			self.seekTo(position: positionEvent.positionTime * 1000)
			if self.hasListeners {
				let positionMs = positionEvent.positionTime * 1000
				let info = self.getPlaybackInfo()
				let payload: [String: Any] = [
					"position": Int(positionMs),
					"duration": info.duration,
					"triggeredBy": self.TRIGGER_SOURCE_SYSTEM
				]
				self.sendEvent(type: self.EVENT_TYPE_SEEK_COMPLETE, track: self.currentTrack, payload: payload)
			}
			return .success
		}

		commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: settingSkipIntervalMs)]
		commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: settingSkipIntervalMs)]

		isRemoteCommandCenterSetup = true
	}

	private func removeRemoteTransportControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		commandCenter.playCommand.removeTarget(nil)
		commandCenter.pauseCommand.removeTarget(nil)
		commandCenter.togglePlayPauseCommand.removeTarget(nil) // Magic Tap cleanup
		commandCenter.nextTrackCommand.removeTarget(nil)
		commandCenter.previousTrackCommand.removeTarget(nil)
		commandCenter.changePlaybackPositionCommand.removeTarget(nil)
		commandCenter.skipForwardCommand.removeTarget(nil)
		commandCenter.skipBackwardCommand.removeTarget(nil)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Ambient Audio Methods
	////////////////////////////////////////////////////////////

	/**
	 * Play an ambient audio track
	 * This is a completely isolated system from the main audio player
	 */
	@objc(ambientPlay:)
	func ambientPlay(options: NSDictionary) {
		// Get the URL from options
		guard let urlString = options["url"] as? String, let url = URL(string: urlString) else {
			onAmbientError("Invalid URL provided to ambientPlay()")
			return
		}

		// Get loop option, default to true if not provided
		settingLoopAmbient = options["loop"] as? Bool ?? true

		log("Ambient Play", urlString, "loop:", settingLoopAmbient)

		// Stop any existing ambient playback
		ambientStop()

		// Create a new player item
		ambientPlayerItem = AVPlayerItem(url: url)

		// Create a new player
		ambientPlayer = AVPlayer(playerItem: ambientPlayerItem)
		ambientPlayer?.volume = activeVolumeAmbient

		// Add observer for track completion
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(ambientPlayerItemDidPlayToEndTime(_:)),
			name: .AVPlayerItemDidPlayToEndTime,
			object: ambientPlayerItem
		)

		// Start playback immediately
		ambientPlayer?.play()
	}

	/**
	 * Stop ambient audio playback
	 */
	@objc(ambientStop)
	func ambientStop() {
		log("Ambient Stop")

		// Remove observer for track completion
		if let item = ambientPlayerItem {
			NotificationCenter.default.removeObserver(
				self,
				name: .AVPlayerItemDidPlayToEndTime,
				object: item
			)
		}

		// Stop and release the player
		ambientPlayer?.pause()
		ambientPlayer = nil
		ambientPlayerItem = nil
	}

	/**
	 * Set the volume of ambient audio playback
	 */
	@objc(ambientSetVolume:)
	func ambientSetVolume(volume: Double) {
		activeVolumeAmbient = Float(volume)
		log("Ambient Set Volume", activeVolumeAmbient)

		// Apply volume to player if it exists
		ambientPlayer?.volume = activeVolumeAmbient
	}

	/**
	 * Pause ambient audio playback
	 * No-op if already paused or not playing
	 */
	@objc(ambientPause)
	func ambientPause() {
		log("Ambient Pause")

		// Pause the player if it exists
		ambientPlayer?.pause()
	}

	/**
	 * Resume ambient audio playback
	 * No-op if already playing or no active track
	 */
	@objc(ambientResume)
	func ambientResume() {
		log("Ambient Resume")

		// Resume the player if it exists
		ambientPlayer?.play()
	}

	/**
	 * Seek to position in ambient audio track
	 * Silently ignore if not supported or no active track
	 *
	 * @param positionMs Position in milliseconds
	 */
	@objc(ambientSeekTo:)
	func ambientSeekTo(positionMs: Double) {
		log("Ambient Seek To", positionMs)

		// Convert milliseconds to seconds for CMTime
		let seconds = positionMs / 1000.0

		// Create a CMTime value for the seek position
		let time = CMTime(seconds: seconds, preferredTimescale: 1000)

		// Seek to the specified position
		ambientPlayer?.seek(to: time)
	}

	/**
	 * Handle ambient track completion
	 */
	@objc private func ambientPlayerItemDidPlayToEndTime(_ notification: Notification) {
		log("Ambient Track Ended")

		if settingLoopAmbient {
			// If looping is enabled, seek to beginning and continue playback
			ambientPlayer?.seek(to: CMTime.zero)
			ambientPlayer?.play()
		} else {
			// If looping is disabled, stop playback and emit event
			ambientStop()
			sendAmbientEvent(type: EVENT_TYPE_AMBIENT_TRACK_ENDED, payload: nil)
		}
	}

	/**
	 * Emit an ambient error event
	 */
	private func onAmbientError(_ message: String) {
		log("Ambient Error:", message)

		// Stop playback
		ambientStop()

		// Emit error event
		let payload: [String: Any] = ["error": message]
		sendAmbientEvent(type: EVENT_TYPE_AMBIENT_ERROR, payload: payload)
	}

	/**
	 * Send an ambient event to JavaScript
	 */
	private func sendAmbientEvent(type: String, payload: [String: Any]?) {
		guard hasListeners else { return }

		var body: [String: Any] = ["type": type]

		if let payload = payload {
			body["payload"] = payload
		}

		sendEvent(withName: AMBIENT_EVENT_NAME, body: body)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Queue & Crossfade Methods
	////////////////////////////////////////////////////////////

	/**
	 * Send a queue event to JavaScript
	 */
	private func sendQueueEvent(type: String, payload: [String: Any]?) {
		guard hasListeners else { return }

		var body: [String: Any] = ["type": type]

		if let payload = payload {
			body["payload"] = payload
		}

		log("Queue Event:", type)
		sendEvent(withName: QUEUE_EVENT_NAME, body: body)
	}

	/**
	 * Get the active player based on the current state
	 */
	private func getActivePlayer() -> AVPlayer? {
		return activePlayerIsA ? playerA : playerB
	}

	/**
	 * Get the inactive player (used for preparing next track)
	 */
	private func getInactivePlayer() -> AVPlayer? {
		return activePlayerIsA ? playerB : playerA
	}

	/**
	 * Get track at specific index in queue, or nil if out of bounds
	 */
	private func getQueueTrack(at index: Int) -> NSDictionary? {
		guard index >= 0 && index < queue.count else { return nil }
		return queue[index]
	}

	/**
	 * Build queue info payload for events
	 */
	private func buildQueueInfoPayload() -> [String: Any] {
		return [
			"currentIndex": currentQueueIndex,
			"queueLength": queue.count,
			"currentTrack": getQueueTrack(at: currentQueueIndex) as Any,
			"nextTrack": getQueueTrack(at: currentQueueIndex + 1) as Any,
			"previousTrack": getQueueTrack(at: currentQueueIndex - 1) as Any
		]
	}

	/**
	 * Load a queue of tracks for playback with crossfade support
	 */
	@objc(loadQueue:withOptions:)
	func loadQueue(tracks: NSArray, options: NSDictionary) {
		log("Loading queue with", tracks.count, "tracks")

		// Reset any existing queue state
		clearQueue()

		// Store the queue
		queue = tracks.compactMap { $0 as? NSDictionary }
		guard queue.count > 0 else {
			onError("Cannot load empty queue")
			return
		}

		isQueueMode = true
		queuePlaybackOptions = options
		currentQueueIndex = options["startIndex"] as? Int ?? 0

		// Clamp startIndex to valid range
		if currentQueueIndex < 0 || currentQueueIndex >= queue.count {
			currentQueueIndex = 0
		}

		// Get crossfade duration (clamped between 0 and 15000ms)
		crossfadeDurationMs = min(15000, max(0, options["crossfadeDurationMs"] as? Double ?? 3000.0))

		// Extract settings from options
		settingDebug = options["debug"] as? Bool ?? false
		settingDebugIncludeProgress = options["debugIncludesProgress"] as? Bool ?? false
		let autoPlay = options["autoPlay"] as? Bool ?? true

		log("Queue loaded:", queue.count, "tracks, crossfade:", crossfadeDurationMs, "ms, startIndex:", currentQueueIndex)

		// Setup audio session
		do {
			let contentType = options["contentType"] as? String ?? "MUSIC"
			let mode: AVAudioSession.Mode = (contentType == "SPEECH") ? .spokenAudio : .default
			try AVAudioSession.sharedInstance().setCategory(.playback, mode: mode)
			try AVAudioSession.sharedInstance().setActive(true)
			setupAudioSessionInterruptionObserver()
		} catch {
			onError("Audio session setup failed: \(error.localizedDescription)")
			return
		}

		// Initialize both players
		initializeQueuePlayers()

		// Load and play the first track
		loadTrackIntoPlayer(isPlayerA: true, trackIndex: currentQueueIndex, startPlayback: autoPlay)

		// Pre-buffer next track if available
		if currentQueueIndex + 1 < queue.count {
			loadTrackIntoPlayer(isPlayerA: false, trackIndex: currentQueueIndex + 1, startPlayback: false)
		}

		// Emit queue changed event
		sendQueueEvent(type: EVENT_TYPE_QUEUE_CHANGED, payload: buildQueueInfoPayload())
	}

	/**
	 * Initialize both players for queue mode
	 */
	private func initializeQueuePlayers() {
		// Clean up existing players
		cleanupQueuePlayers()

		// Create player instances (items will be set when loading tracks)
		playerA = AVPlayer()
		playerB = AVPlayer()

		playerA?.volume = activeVolume
		playerB?.volume = 0 // Start muted for crossfade

		activePlayerIsA = true
	}

	/**
	 * Load a track into a specific player
	 */
	private func loadTrackIntoPlayer(isPlayerA: Bool, trackIndex: Int, startPlayback: Bool) {
		guard trackIndex >= 0 && trackIndex < queue.count else { return }

		let track = queue[trackIndex]
		guard let urlString = track["url"] as? String,
			  let url = URL(string: urlString) else {
			log("Invalid track URL at index", trackIndex)
			return
		}

		let player = isPlayerA ? playerA : playerB

		// Remove existing observers
		removePlayerObservers(isPlayerA: isPlayerA)

		// Create player item with headers if provided
		let item: AVPlayerItem
		if let headers = queuePlaybackOptions?["headers"] as? NSDictionary,
		   let audioHeaders = headers["audio"] as? NSDictionary {
			var headerFields = [String: String]()
			for (key, value) in audioHeaders {
				if let headerField = key as? String, let headerValue = value as? String {
					headerFields[headerField] = headerValue
				}
			}
			let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headerFields])
			item = AVPlayerItem(asset: asset)
		} else {
			item = AVPlayerItem(url: url)
		}

		// Store item reference
		if isPlayerA {
			playerAItem = item
		} else {
			playerBItem = item
		}

		// Add observers
		item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
		if isPlayerA {
			isPlayerAStatusObserverAdded = true
		} else {
			isPlayerBStatusObserverAdded = true
		}

		// Replace current item
		player?.replaceCurrentItem(with: item)

		// Add rate observer
		player?.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
		if isPlayerA {
			isPlayerARateObserverAdded = true
		} else {
			isPlayerBRateObserverAdded = true
		}

		// Add end notification
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(queuePlayerItemDidPlayToEndTime(_:)),
			name: .AVPlayerItemDidPlayToEndTime,
			object: item
		)

		log("Loaded track into player", isPlayerA ? "A" : "B", "at index", trackIndex, "startPlayback:", startPlayback)

		if startPlayback {
			shouldBePlaying = true
			currentTrack = track
			player?.volume = activeVolume
			player?.play()

			// Apply playback speed
			if currentPlaybackSpeed != 1.0 {
				player?.rate = currentPlaybackSpeed
			}

			// Update now playing info
			updateNowPlayingInfoForQueueTrack(track)
			setupRemoteTransportControls()

			// Start progress timer
			startProgressTimer()

			// Emit state change
			sendStateEvent(state: STATE_PLAYING, track: track)
		}
	}

	/**
	 * Remove observers from a player
	 */
	private func removePlayerObservers(isPlayerA: Bool) {
		let player = isPlayerA ? playerA : playerB
		let item = isPlayerA ? playerAItem : playerBItem

		if isPlayerA {
			if isPlayerARateObserverAdded {
				player?.removeObserver(self, forKeyPath: "rate")
				isPlayerARateObserverAdded = false
			}
			if isPlayerAStatusObserverAdded, let item = item {
				item.removeObserver(self, forKeyPath: "status")
				isPlayerAStatusObserverAdded = false
			}
		} else {
			if isPlayerBRateObserverAdded {
				player?.removeObserver(self, forKeyPath: "rate")
				isPlayerBRateObserverAdded = false
			}
			if isPlayerBStatusObserverAdded, let item = item {
				item.removeObserver(self, forKeyPath: "status")
				isPlayerBStatusObserverAdded = false
			}
		}

		if let item = item {
			NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
		}
	}

	/**
	 * Clean up queue players
	 */
	private func cleanupQueuePlayers() {
		// Stop crossfade if in progress
		crossfadeTimer?.invalidate()
		crossfadeTimer = nil
		isCrossfading = false

		// Remove observers and stop players
		removePlayerObservers(isPlayerA: true)
		removePlayerObservers(isPlayerA: false)

		playerA?.pause()
		playerB?.pause()
		playerA = nil
		playerB = nil
		playerAItem = nil
		playerBItem = nil
	}

	/**
	 * Update now playing info for a queue track
	 */
	private func updateNowPlayingInfoForQueueTrack(_ track: NSDictionary) {
		var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

		if let title = track["title"] as? String {
			nowPlayingInfo[MPMediaItemPropertyTitle] = title
		}
		if let artist = track["artist"] as? String {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artist
		}
		if let album = track["album"] as? String {
			nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
		}

		nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

		if let player = getActivePlayer(), let item = player.currentItem {
			let duration = item.duration.seconds
			if !duration.isNaN && !duration.isInfinite {
				nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
			}
		}

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

		// Fetch artwork asynchronously
		if let artworkUrlString = track["artwork"] as? String,
		   let artworkUrl = URL(string: artworkUrlString) {
			fetchArtworkAsync(url: artworkUrl)
		}
	}

	/**
	 * Fetch artwork asynchronously and update now playing info
	 */
	private func fetchArtworkAsync(url: URL) {
		DispatchQueue.global().async { [weak self] in
			guard let self = self else { return }

			do {
				// Check for artwork headers
				if let headers = self.queuePlaybackOptions?["headers"] as? NSDictionary,
				   let artworkHeaders = headers["artwork"] as? NSDictionary {
					var request = URLRequest(url: url)
					for (key, value) in artworkHeaders {
						if let headerField = key as? String, let headerValue = value as? String {
							request.setValue(headerValue, forHTTPHeaderField: headerField)
						}
					}

					let semaphore = DispatchSemaphore(value: 0)
					var imageData: Data? = nil

					URLSession.shared.dataTask(with: request) { (data, _, _) in
						imageData = data
						semaphore.signal()
					}.resume()

					semaphore.wait()

					if let data = imageData, let image = UIImage(data: data) {
						let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
						DispatchQueue.main.async {
							var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
							info[MPMediaItemPropertyArtwork] = artwork
							MPNowPlayingInfoCenter.default().nowPlayingInfo = info
						}
					}
				} else {
					let data = try Data(contentsOf: url)
					if let image = UIImage(data: data) {
						let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
						DispatchQueue.main.async {
							var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
							info[MPMediaItemPropertyArtwork] = artwork
							MPNowPlayingInfoCenter.default().nowPlayingInfo = info
						}
					}
				}
			} catch {
				self.log("Failed to fetch artwork:", error.localizedDescription)
			}
		}
	}

	/**
	 * Check if crossfade should start based on current playback position
	 */
	private func checkForCrossfadeStart() {
		guard isQueueMode && !isCrossfading else { return }
		guard currentQueueIndex + 1 < queue.count else { return }
		guard crossfadeDurationMs > 0 else { return }

		guard let player = getActivePlayer(),
			  let item = player.currentItem else { return }

		let currentTime = player.currentTime().seconds
		let duration = item.duration.seconds

		guard !currentTime.isNaN && !duration.isNaN &&
			  !currentTime.isInfinite && !duration.isInfinite else { return }

		let remainingTimeMs = (duration - currentTime) * 1000

		// Start crossfade when remaining time equals crossfade duration
		if remainingTimeMs <= crossfadeDurationMs && remainingTimeMs > 0 {
			startCrossfade()
		}
	}

	/**
	 * Start crossfade transition to next track
	 */
	private func startCrossfade() {
		guard !isCrossfading else {
			log("Crossfade already in progress, ignoring")
			return
		}
		guard currentQueueIndex + 1 < queue.count else {
			log("No next track available for crossfade")
			return
		}

		let activePlayer = getActivePlayer()
		let inactivePlayer = getInactivePlayer()

		guard let activePlayer = activePlayer, let inactivePlayer = inactivePlayer else {
			log("Missing player reference for crossfade")
			return
		}

		// Check if inactive player has a loaded item
		guard let inactiveItem = inactivePlayer.currentItem else {
			log("Inactive player has no item loaded, loading now")
			loadTrackIntoPlayer(isPlayerA: !activePlayerIsA, trackIndex: currentQueueIndex + 1, startPlayback: false)
			// Retry crossfade after a short delay to allow loading
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.startCrossfade()
			}
			return
		}

		// Check if inactive player item is ready
		if inactiveItem.status != .readyToPlay {
			log("Inactive player item not ready (status: \(inactiveItem.status.rawValue)), waiting...")
			// Retry crossfade after a short delay
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
				self?.startCrossfade()
			}
			return
		}

		isCrossfading = true
		log("Starting crossfade from index", currentQueueIndex, "to", currentQueueIndex + 1)

		// Emit crossfade started event
		sendQueueEvent(type: EVENT_TYPE_CROSSFADE_STARTED, payload: [
			"fromIndex": currentQueueIndex,
			"toIndex": currentQueueIndex + 1,
			"fromTrack": queue[currentQueueIndex],
			"toTrack": queue[currentQueueIndex + 1]
		])

		// Start the inactive player
		inactivePlayer.volume = 0
		inactivePlayer.play()

		// Apply playback speed to inactive player
		if currentPlaybackSpeed != 1.0 {
			inactivePlayer.rate = currentPlaybackSpeed
		}

		// Animate crossfade on main thread
		let fadeDuration = crossfadeDurationMs / 1000.0
		let steps = 30
		let interval = fadeDuration / Double(steps)

		crossfadeTimer?.invalidate()

		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }

			var currentStep = 0

			self.crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
				guard let self = self else {
					timer.invalidate()
					return
				}

				currentStep += 1
				let progress = Float(currentStep) / Float(steps)

				self.log("Crossfade step", currentStep, "/", steps, "progress:", progress)

				// Fade out active, fade in inactive
				activePlayer.volume = self.activeVolume * (1.0 - progress)
				inactivePlayer.volume = self.activeVolume * progress

				if currentStep >= steps {
					timer.invalidate()
					self.log("Crossfade timer completed, calling completeCrossfade")
					self.completeCrossfade()
				}
			}

			// Ensure timer is added to run loop
			if let timer = self.crossfadeTimer {
				RunLoop.current.add(timer, forMode: .common)
			}
		}
	}

	/**
	 * Complete the crossfade transition
	 */
	private func completeCrossfade() {
		let previousPlayer = getActivePlayer()

		// Swap active player
		activePlayerIsA = !activePlayerIsA
		currentQueueIndex += 1
		currentTrack = queue[currentQueueIndex]

		// Ensure volumes are correct
		getActivePlayer()?.volume = activeVolume
		previousPlayer?.volume = 0

		// Stop and reset previous player
		previousPlayer?.pause()
		previousPlayer?.seek(to: .zero)

		isCrossfading = false
		crossfadeTimer = nil

		log("Crossfade completed, now at index", currentQueueIndex)

		// Update now playing info
		if let track = currentTrack {
			updateNowPlayingInfoForQueueTrack(track)
		}

		// Reset lastEmittedState to allow PLAYING to be emitted for the new track
		lastEmittedState = ""

		// Emit PLAYING state for the new track
		sendStateEvent(state: STATE_PLAYING, track: currentTrack)

		// Emit queue events
		sendQueueEvent(type: EVENT_TYPE_CROSSFADE_COMPLETED, payload: buildQueueInfoPayload())
		sendQueueEvent(type: EVENT_TYPE_QUEUE_TRACK_CHANGED, payload: buildQueueInfoPayload())

		// Pre-buffer next track if available
		if currentQueueIndex + 1 < queue.count {
			loadTrackIntoPlayer(isPlayerA: !activePlayerIsA, trackIndex: currentQueueIndex + 1, startPlayback: false)
		}
	}

	/**
	 * Handle queue player item did play to end time
	 */
	@objc private func queuePlayerItemDidPlayToEndTime(_ notification: Notification) {
		guard isQueueMode else { return }

		// If crossfade is in progress, let it complete naturally
		if isCrossfading {
			return
		}

		log("Queue track ended at index", currentQueueIndex)

		// Check if there's a next track
		if currentQueueIndex + 1 < queue.count {
			// Move to next track without crossfade (track ended naturally)
			skipToNextInternal(withCrossfade: false)
		} else {
			// Queue has ended
			log("Queue ended")
			shouldBePlaying = false
			stopTimer()
			updateNowPlayingInfo(time: 0, rate: 0)
			sendStateEvent(state: STATE_STOPPED, position: 0, duration: 0, track: currentTrack)
			sendQueueEvent(type: EVENT_TYPE_QUEUE_ENDED, payload: buildQueueInfoPayload())
		}
	}

	/**
	 * Skip to next track in queue
	 */
	@objc(skipToNext)
	func skipToNext() {
		guard isQueueMode else {
			log("skipToNext ignored - not in queue mode")
			return
		}

		skipToNextInternal(withCrossfade: crossfadeDurationMs > 0)
	}

	/**
	 * Internal method to skip to next track with optional crossfade
	 */
	private func skipToNextInternal(withCrossfade: Bool) {
		guard currentQueueIndex + 1 < queue.count else {
			log("skipToNext ignored - already at last track")
			return
		}

		if withCrossfade && !isCrossfading {
			startCrossfade()
		} else if !isCrossfading {
			// Immediate transition without crossfade
			let previousPlayer = getActivePlayer()
			previousPlayer?.pause()
			previousPlayer?.seek(to: .zero)

			activePlayerIsA = !activePlayerIsA
			currentQueueIndex += 1
			currentTrack = queue[currentQueueIndex]

			// Load and play new track
			loadTrackIntoPlayer(isPlayerA: activePlayerIsA, trackIndex: currentQueueIndex, startPlayback: shouldBePlaying)

			// Pre-buffer next track
			if currentQueueIndex + 1 < queue.count {
				loadTrackIntoPlayer(isPlayerA: !activePlayerIsA, trackIndex: currentQueueIndex + 1, startPlayback: false)
			}

			sendQueueEvent(type: EVENT_TYPE_QUEUE_TRACK_CHANGED, payload: buildQueueInfoPayload())
		}
	}

	/**
	 * Skip to previous track in queue
	 */
	@objc(skipToPrevious)
	func skipToPrevious() {
		guard isQueueMode else {
			log("skipToPrevious ignored - not in queue mode")
			return
		}

		guard currentQueueIndex > 0 else {
			// At first track, just seek to beginning
			getActivePlayer()?.seek(to: .zero)
			return
		}

		// Cancel any ongoing crossfade
		crossfadeTimer?.invalidate()
		crossfadeTimer = nil
		isCrossfading = false

		let previousPlayer = getActivePlayer()
		previousPlayer?.pause()
		previousPlayer?.volume = 0

		activePlayerIsA = !activePlayerIsA
		currentQueueIndex -= 1
		currentTrack = queue[currentQueueIndex]

		// Load and play previous track
		loadTrackIntoPlayer(isPlayerA: activePlayerIsA, trackIndex: currentQueueIndex, startPlayback: shouldBePlaying)

		// Pre-buffer next track (which is the one we just left)
		loadTrackIntoPlayer(isPlayerA: !activePlayerIsA, trackIndex: currentQueueIndex + 1, startPlayback: false)

		sendQueueEvent(type: EVENT_TYPE_QUEUE_TRACK_CHANGED, payload: buildQueueInfoPayload())
	}

	/**
	 * Skip to a specific index in the queue
	 */
	@objc(skipToQueueIndex:)
	func skipToQueueIndex(index: Int) {
		guard isQueueMode else {
			log("skipToQueueIndex ignored - not in queue mode")
			return
		}

		guard index >= 0 && index < queue.count else {
			log("skipToQueueIndex ignored - index out of bounds")
			return
		}

		if index == currentQueueIndex {
			// Same track, just seek to beginning
			getActivePlayer()?.seek(to: .zero)
			return
		}

		// Cancel any ongoing crossfade
		crossfadeTimer?.invalidate()
		crossfadeTimer = nil
		isCrossfading = false

		let previousPlayer = getActivePlayer()
		previousPlayer?.pause()
		previousPlayer?.volume = 0

		activePlayerIsA = !activePlayerIsA
		currentQueueIndex = index
		currentTrack = queue[currentQueueIndex]

		// Load and play the track at the specified index
		loadTrackIntoPlayer(isPlayerA: activePlayerIsA, trackIndex: currentQueueIndex, startPlayback: shouldBePlaying)

		// Pre-buffer next track if available
		if currentQueueIndex + 1 < queue.count {
			loadTrackIntoPlayer(isPlayerA: !activePlayerIsA, trackIndex: currentQueueIndex + 1, startPlayback: false)
		}

		sendQueueEvent(type: EVENT_TYPE_QUEUE_TRACK_CHANGED, payload: buildQueueInfoPayload())
	}

	/**
	 * Set the crossfade duration
	 */
	@objc(setCrossfadeDuration:)
	func setCrossfadeDuration(durationMs: Double) {
		crossfadeDurationMs = min(15000, max(0, durationMs))
		log("Crossfade duration set to", crossfadeDurationMs, "ms")
	}

	/**
	 * Get current queue info
	 */
	@objc(getQueueInfo:rejecter:)
	func getQueueInfo(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
		let info: [String: Any] = [
			"queue": queue,
			"currentIndex": currentQueueIndex,
			"queueLength": queue.count,
			"crossfadeDurationMs": crossfadeDurationMs,
			"isQueueMode": isQueueMode,
			"isCrossfading": isCrossfading
		]
		resolver(info)
	}

	/**
	 * Clear the queue and reset to single-track mode
	 */
	@objc(clearQueue)
	func clearQueue() {
		log("Clearing queue")

		// Stop crossfade if in progress
		crossfadeTimer?.invalidate()
		crossfadeTimer = nil
		isCrossfading = false

		// Clean up queue players
		cleanupQueuePlayers()

		// Reset queue state
		queue = []
		currentQueueIndex = 0
		queuePlaybackOptions = nil
		isQueueMode = false

		// Reset to using the main single player
		activePlayerIsA = true
	}

	/**
	 * Pause queue playback
	 */
	@objc(queuePause)
	func queuePause() {
		guard isQueueMode else { return }

		shouldBePlaying = false
		getActivePlayer()?.pause()

		// Also pause inactive player if crossfading
		if isCrossfading {
			getInactivePlayer()?.pause()
		}

		stopTimer()
		sendPausedStateEvent()
		updateNowPlayingInfo(time: getActivePlayer()?.currentTime().seconds ?? 0, rate: 0)
	}

	/**
	 * Resume queue playback
	 */
	@objc(queueResume)
	func queueResume() {
		guard isQueueMode else { return }

		shouldBePlaying = true

		do {
			if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
				try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
			}
		} catch {
			log("Failed to reactivate audio session:", error.localizedDescription)
		}

		getActivePlayer()?.play()

		// Also resume inactive player if crossfading
		if isCrossfading {
			getInactivePlayer()?.play()
		}

		// Apply playback speed
		if currentPlaybackSpeed != 1.0 {
			getActivePlayer()?.rate = currentPlaybackSpeed
			if isCrossfading {
				getInactivePlayer()?.rate = currentPlaybackSpeed
			}
		}

		startProgressTimer()
		sendPlayingStateEvent()
		updateNowPlayingInfo(time: getActivePlayer()?.currentTime().seconds ?? 0, rate: 1.0)
	}

	/**
	 * Seek within current queue track
	 */
	@objc(queueSeekTo:)
	func queueSeekTo(positionMs: Double) {
		guard isQueueMode else { return }
		guard let player = getActivePlayer() else { return }

		let position = positionMs / 1000.0
		let time = CMTime(seconds: position, preferredTimescale: 1000)

		player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
			guard let self = self, completed else { return }
			self.updateNowPlayingInfoWithCurrentTime(position)

			if self.hasListeners {
				let info = self.getPlaybackInfo()
				let payload: [String: Any] = [
					"position": Int(positionMs),
					"duration": info.duration,
					"triggeredBy": self.TRIGGER_SOURCE_USER
				]
				self.sendEvent(type: self.EVENT_TYPE_SEEK_COMPLETE, track: self.currentTrack, payload: payload)
			}
		}
	}

	/**
	 * Override progress timer to check for crossfade
	 */
	private func sendQueueProgressNoticeEvent() {
		guard isQueueMode else { return }
		guard let player = getActivePlayer(), player.rate != 0 else { return }

		// Check if crossfade should start
		checkForCrossfadeStart()

		// Send regular progress event
		let info = getQueuePlaybackInfo()
		let payload: [String: Any] = [
			"position": info.position,
			"duration": info.duration
		]
		sendEvent(type: EVENT_TYPE_PROGRESS, track: info.track, payload: payload)
	}

	/**
	 * Get playback info for queue mode
	 */
	private func getQueuePlaybackInfo() -> (position: Int, duration: Int, track: NSDictionary?) {
		guard let player = getActivePlayer(), let currentItem = player.currentItem else {
			return (0, 0, currentTrack)
		}

		let currentTimeSec = player.currentTime().seconds
		let durationSec = currentItem.duration.seconds
		let validCurrentTimeSec = (currentTimeSec.isNaN || currentTimeSec.isInfinite) ? 0 : currentTimeSec
		let validDurationSec = (durationSec.isNaN || durationSec.isInfinite) ? 0 : durationSec

		let positionMs = Int(round(validCurrentTimeSec * 1000))
		let durationMs = Int(round(validDurationSec * 1000))

		let sanitizedPositionMs = positionMs < 0 ? 0 : positionMs
		let sanitizedDurationMs = durationMs < 0 ? 0 : durationMs

		return (position: sanitizedPositionMs, duration: sanitizedDurationMs, track: currentTrack)
	}
}
