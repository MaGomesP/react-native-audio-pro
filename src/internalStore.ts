import { create } from 'zustand';

import { normalizeVolume } from './utils';
import {
	AudioProEventType,
	AudioProQueueEventType,
	AudioProState,
	DEFAULT_CONFIG,
	DEFAULT_CROSSFADE_DURATION_MS,
} from './values';

import type {
	AudioProConfigureOptions,
	AudioProEvent,
	AudioProPlaybackErrorPayload,
	AudioProQueueEvent,
	AudioProTrack,
} from './types';

export interface AudioProStore {
	playerState: AudioProState;
	position: number;
	duration: number;
	playbackSpeed: number;
	volume: number;
	debug: boolean;
	debugIncludesProgress: boolean;
	trackPlaying: AudioProTrack | null;
	configureOptions: AudioProConfigureOptions;
	error: AudioProPlaybackErrorPayload | null;
	// Queue state
	queue: AudioProTrack[];
	currentQueueIndex: number;
	crossfadeDurationMs: number;
	isCrossfading: boolean;
	// Actions
	setDebug: (debug: boolean) => void;
	setDebugIncludesProgress: (includeProgress: boolean) => void;
	setTrackPlaying: (track: AudioProTrack | null) => void;
	setConfigureOptions: (options: AudioProConfigureOptions) => void;
	setPlaybackSpeed: (speed: number) => void;
	setVolume: (volume: number) => void;
	setError: (error: AudioProPlaybackErrorPayload | null) => void;
	// Queue actions
	setQueue: (tracks: AudioProTrack[]) => void;
	addTrackToQueue: (track: AudioProTrack, position?: number) => void;
	setCurrentQueueIndex: (index: number) => void;
	setCrossfadeDurationMs: (duration: number) => void;
	setIsCrossfading: (isCrossfading: boolean) => void;
	clearQueue: () => void;
	updateFromEvent: (event: AudioProEvent) => void;
	updateFromQueueEvent: (event: AudioProQueueEvent) => void;
}

export const internalStore = create<AudioProStore>((set, get) => ({
	playerState: AudioProState.IDLE,
	position: 0,
	duration: 0,
	playbackSpeed: 1.0,
	volume: normalizeVolume(1.0),
	debug: false,
	debugIncludesProgress: false,
	trackPlaying: null,
	configureOptions: { ...DEFAULT_CONFIG },
	error: null,
	// Queue state
	queue: [],
	currentQueueIndex: 0,
	crossfadeDurationMs: DEFAULT_CROSSFADE_DURATION_MS,
	isCrossfading: false,
	// Actions
	setDebug: (debug) => set({ debug }),
	setDebugIncludesProgress: (includeProgress) => set({ debugIncludesProgress: includeProgress }),
	setTrackPlaying: (track) => set({ trackPlaying: track }),
	setConfigureOptions: (options) => set({ configureOptions: options }),
	setPlaybackSpeed: (speed) => set({ playbackSpeed: speed }),
	setVolume: (volume) => set({ volume: normalizeVolume(volume) }),
	setError: (error) => set({ error }),
	// Queue actions
	setQueue: (tracks) => set({ queue: tracks, currentQueueIndex: 0 }),
	addTrackToQueue: (track, position) => {
		const { queue } = get();
		const insertPosition =
			position !== undefined ? Math.max(0, Math.min(position, queue.length)) : queue.length;
		const newQueue = [...queue];
		newQueue.splice(insertPosition, 0, track);
		set({ queue: newQueue });
	},
	setCurrentQueueIndex: (index) => set({ currentQueueIndex: index }),
	setCrossfadeDurationMs: (duration) => set({ crossfadeDurationMs: duration }),
	setIsCrossfading: (isCrossfading) => set({ isCrossfading }),
	clearQueue: () => set({ queue: [], currentQueueIndex: 0, isCrossfading: false }),
	updateFromEvent: (event) => {
		// Early exit for simple remote commands (no state change)
		if (
			event.type === AudioProEventType.REMOTE_NEXT ||
			event.type === AudioProEventType.REMOTE_PREV
		) {
			return;
		}

		const { type, track, payload } = event;
		const current = get();
		const updates: Partial<AudioProStore> = {};

		// Warn if a non-error event has no track
		if (track === undefined && type !== AudioProEventType.PLAYBACK_ERROR) {
			console.warn(`[react-native-audio-pro]: Event ${type} missing required track property`);
		}

		// 1. State changes
		if (
			type === AudioProEventType.STATE_CHANGED &&
			payload?.state &&
			payload.state !== current.playerState
		) {
			updates.playerState = payload.state;
			// Clear error when leaving ERROR state
			if (payload.state !== AudioProState.ERROR && current.error !== null) {
				updates.error = null;
			}
			// Clear queue state when transitioning to IDLE (e.g., after clear())
			if (payload.state === AudioProState.IDLE && current.queue.length > 0) {
				updates.queue = [];
				updates.currentQueueIndex = 0;
				updates.isCrossfading = false;
			}
		}

		// 2. Playback errors
		// According to the contract in logic.md:
		// - PLAYBACK_ERROR and ERROR state are separate and must not be conflated
		// - ERROR state must be explicitly triggered by native logic
		// - PLAYBACK_ERROR events should not automatically imply or trigger a STATE_CHANGED: ERROR
		if (type === AudioProEventType.PLAYBACK_ERROR && payload?.error) {
			updates.error = {
				error: payload.error,
				errorCode: payload.errorCode,
			};
			// Note: We do NOT automatically transition to ERROR state here
			// Native code is responsible for emitting STATE_CHANGED: ERROR if needed
		}

		// 2.5 Track ended
		// According to the contract in logic.md:
		// - Native is responsible for detecting the end of a track
		// - Native must emit both STATE_CHANGED: STOPPED and TRACK_ENDED
		// - TypeScript should not infer or emit state transitions on its own
		if (type === AudioProEventType.TRACK_ENDED) {
			// Note: We do NOT automatically transition to STOPPED state here
			// Native code is responsible for emitting STATE_CHANGED: STOPPED
			// We only receive the TRACK_ENDED event for informational purposes
		}

		// 3. Speed changes
		if (
			type === AudioProEventType.PLAYBACK_SPEED_CHANGED &&
			payload?.speed !== undefined &&
			payload.speed !== current.playbackSpeed
		) {
			updates.playbackSpeed = payload.speed;
		}

		// 4. Progress updates
		if (payload?.position !== undefined && payload.position !== current.position) {
			updates.position = payload.position;
		}
		if (payload?.duration !== undefined && payload.duration !== current.duration) {
			updates.duration = payload.duration;
		}

		// 5. Track loading/unloading
		if (track) {
			const prev = current.trackPlaying;
			// Only update if the track object has changed
			if (
				!prev ||
				track.id !== prev.id ||
				track.url !== prev.url ||
				track.title !== prev.title ||
				track.artwork !== prev.artwork ||
				track.album !== prev.album ||
				track.artist !== prev.artist
			) {
				updates.trackPlaying = track;
			}
		} else if (
			track === null &&
			type !== AudioProEventType.PLAYBACK_ERROR &&
			current.trackPlaying !== null
		) {
			// Explicit unload of track (not during error)
			updates.trackPlaying = null;
		}

		// 6. Apply batched updates
		if (Object.keys(updates).length > 0) {
			set(updates);
		}
	},
	updateFromQueueEvent: (event) => {
		const { type, payload } = event;
		const updates: Partial<AudioProStore> = {};

		switch (type) {
			case AudioProQueueEventType.QUEUE_CHANGED:
				if (payload?.currentIndex !== undefined) {
					updates.currentQueueIndex = payload.currentIndex;
				}
				if (payload?.currentTrack) {
					updates.trackPlaying = payload.currentTrack;
				}
				break;

			case AudioProQueueEventType.QUEUE_TRACK_CHANGED:
				if (payload?.currentIndex !== undefined) {
					updates.currentQueueIndex = payload.currentIndex;
				}
				if (payload?.currentTrack) {
					updates.trackPlaying = payload.currentTrack;
				}
				break;

			case AudioProQueueEventType.CROSSFADE_STARTED:
				updates.isCrossfading = true;
				break;

			case AudioProQueueEventType.CROSSFADE_COMPLETED:
				updates.isCrossfading = false;
				if (payload?.currentIndex !== undefined) {
					updates.currentQueueIndex = payload.currentIndex;
				}
				if (payload?.currentTrack) {
					updates.trackPlaying = payload.currentTrack;
				}
				break;

			case AudioProQueueEventType.QUEUE_ENDED:
				updates.isCrossfading = false;
				break;
		}

		if (Object.keys(updates).length > 0) {
			set(updates);
		}
	},
}));
