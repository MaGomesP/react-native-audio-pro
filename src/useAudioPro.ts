import { useShallow } from 'zustand/react/shallow';

import { internalStore } from './internalStore';

/**
 * React hook for accessing the current state of the audio player
 *
 * @returns An object containing the current state of the audio player:
 * - state: The current playback state
 * - position: Current playback position in milliseconds
 * - duration: Total duration of the current track in milliseconds
 * - playingTrack: The currently playing track or null if no track is playing
 * - playbackSpeed: Current playback speed (1.0 is normal speed)
 * - volume: Current volume level (0.0 to 1.0)
 * - error: Current error state or null if no error exists
 * - queue: Array of tracks in the queue
 * - currentQueueIndex: Current index in the queue
 * - crossfadeDurationMs: Duration of crossfade in milliseconds
 * - isCrossfading: Whether a crossfade is currently in progress
 */
export const useAudioPro = () => {
	const {
		state,
		position,
		duration,
		playingTrack,
		playbackSpeed,
		volume,
		error,
		queue,
		currentQueueIndex,
		crossfadeDurationMs,
		isCrossfading,
	} = internalStore(
		useShallow((zustandState) => ({
			state: zustandState.playerState,
			position: zustandState.position,
			duration: zustandState.duration,
			playingTrack: zustandState.trackPlaying,
			playbackSpeed: zustandState.playbackSpeed,
			volume: zustandState.volume,
			error: zustandState.error,
			// Queue state
			queue: zustandState.queue,
			currentQueueIndex: zustandState.currentQueueIndex,
			crossfadeDurationMs: zustandState.crossfadeDurationMs,
			isCrossfading: zustandState.isCrossfading,
		})),
	);
	return {
		state,
		position,
		duration,
		playingTrack,
		playbackSpeed,
		volume,
		error,
		// Queue state
		queue,
		currentQueueIndex,
		crossfadeDurationMs,
		isCrossfading,
	};
};
