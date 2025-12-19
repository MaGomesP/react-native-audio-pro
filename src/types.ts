import {
	AudioProTriggerSource,
	AudioProAmbientEventType,
	AudioProContentType,
	AudioProEventType,
	AudioProQueueEventType,
	AudioProState,
} from './values';

// ==============================
// TRACK
// ==============================

export type AudioProArtwork = string;

export type AudioProTrack = {
	id: string;
	url: string;
	title: string;
	artwork: AudioProArtwork;
	album?: string;
	artist?: string;
	[key: string]: unknown; // custom properties
};

// ==============================
// CONFIGURE OPTIONS
// ==============================

export type AudioProConfigureOptions = {
	contentType?: AudioProContentType;
	debug?: boolean;
	debugIncludesProgress?: boolean;
	progressIntervalMs?: number;
	showNextPrevControls?: boolean;
	showSkipControls?: boolean;
	skipIntervalMs?: number;
	/**
	 * @deprecated use skipIntervalMs instead
	 */
	skipInterval?: number;
};

// ==============================
// PLAY OPTIONS
// ==============================

export type AudioProHeaders = {
	audio?: Record<string, string>;
	artwork?: Record<string, string>;
};

export type AudioProPlayOptions = {
	autoPlay?: boolean;
	headers?: AudioProHeaders;
	startTimeMs?: number;
};

// ==============================
// QUEUE OPTIONS
// ==============================

export type AudioProQueueOptions = {
	/** Whether to start playing immediately after loading the queue (default: true) */
	autoPlay?: boolean;
	/** Custom HTTP headers for audio and artwork requests */
	headers?: AudioProHeaders;
	/** Duration of crossfade transition in milliseconds (default: 3000, max: 15000) */
	crossfadeDurationMs?: number;
	/** Index to start playing from (default: 0) */
	startIndex?: number;
};

// ==============================
// EVENTS
// ==============================

export type AudioProEventCallback = (event: AudioProEvent) => void;

export interface AudioProEvent {
	type: AudioProEventType;
	track: AudioProTrack | null; // Required for all events except REMOTE_NEXT and REMOTE_PREV
	payload?: {
		state?: AudioProState;
		position?: number;
		duration?: number;
		error?: string;
		errorCode?: number;
		speed?: number;
	};
}

export interface AudioProStateChangedPayload {
	state: AudioProState;
	position: number;
	duration: number;
}

export interface AudioProTrackEndedPayload {
	position: number;
	duration: number;
}

export interface AudioProPlaybackErrorPayload {
	error: string;
	errorCode?: number;
}

export interface AudioProProgressPayload {
	position: number;
	duration: number;
}

export interface AudioProSeekCompletePayload {
	position: number;
	duration: number;
	/** Indicates who initiated the seek: user or system */
	triggeredBy: AudioProTriggerSource;
}

export interface AudioProPlaybackSpeedChangedPayload {
	speed: number;
}

// ==============================
// AMBIENT AUDIO
// ==============================

export interface AmbientAudioPlayOptions {
	url: string;
	loop?: boolean;
}

export type AudioProAmbientEventCallback = (event: AudioProAmbientEvent) => void;

export interface AudioProAmbientEvent {
	type: AudioProAmbientEventType;
	payload?: {
		error?: string;
	};
}

export interface AudioProAmbientErrorPayload {
	error: string;
}

// ==============================
// QUEUE EVENTS
// ==============================

export type AudioProQueueEventCallback = (event: AudioProQueueEvent) => void;

export interface AudioProQueueEvent {
	type: AudioProQueueEventType;
	payload?: {
		/** Current index in the queue */
		currentIndex?: number;
		/** Total number of tracks in the queue */
		queueLength?: number;
		/** Current track being played */
		currentTrack?: AudioProTrack | null;
		/** Next track in the queue (if any) */
		nextTrack?: AudioProTrack | null;
		/** Previous track in the queue (if any) */
		previousTrack?: AudioProTrack | null;
	};
}

export interface AudioProQueueChangedPayload {
	currentIndex: number;
	queueLength: number;
	currentTrack: AudioProTrack | null;
	nextTrack: AudioProTrack | null;
	previousTrack: AudioProTrack | null;
}

export interface AudioProCrossfadePayload {
	fromTrack: AudioProTrack | null;
	toTrack: AudioProTrack | null;
	progress?: number;
}
