# React Native Audio Pro

Modern, background-capable audio playback for React Native — built for podcasts, audiobooks, and long-form media. Works out of the box with background playback, lock screen controls, and clean hooks-based state. Under the hood: Android uses Media3 (not old-school ExoPlayer), giving you up-to-date media session support without any of the legacy baggage. iOS uses AVFoundation, Apple's native audio engine for professional-grade media playback.

[![npm version](https://img.shields.io/npm/v/react-native-audio-pro?logo=npm&logoColor=white&labelColor=grey&color=blue)](https://www.npmjs.com/package/react-native-audio-pro)
[![website](https://img.shields.io/badge/website-rnap.dev-grey?logo=google-chrome&logoColor=white&color=blue)](https://rnap.dev)
[![GitHub](https://img.shields.io/badge/evergrace--co-react--native--audio--pro-grey?logo=github&logoColor=white&labelColor=grey&color=blue)](https://github.com/evergrace-co/react-native-audio-pro)

## Table of Contents

- [🚀 Installation](#-installation)
- [⚙️ Requirements](#-requirements)
- [🔧 Platform-Specific Setup](#-platform-specific-setup)
  - [🍎 iOS](#ios)
  - [🤖 Android](#android)
- [📚 API Overview](#api-overview)
  - [🛠 Methods](#methods)
  - [🎧 Event Listeners](#event-listeners)
  - [🧱 Enums](#enums)
  - [🧩 Types](#types)
- [⚡️ useAudioPro Hook Example](#useaudiopro-hook-example)
- [📦 API Usage Example](#api-usage-example)
- [📱 Example App](#-example-app)
- [🤝 Contributing](#contributing)
- [🪪 License](#license)

## 🚀 Installation

```bash
npm install react-native-audio-pro
```
or
```bash
yarn add react-native-audio-pro
```

## ⚙️ Requirements

- **TypeScript:** 5.0 or higher
- **React Native:** 0.72 or higher
- **iOS:** iOS 15.1 or higher
- **Android:** Android 7.0 (API 24) or higher (tested on API 28+)

## 🔧 Platform-Specific Setup

### 🍎 iOS

#### Enable Background Modes

1. Open your project settings in Xcode.
2. Go to **Signing & Capabilities**.
3. Add **Background Modes** and enable **Audio, AirPlay, and Picture in Picture**.

### 🤖 Android

> **SDK Support:** Android 7.0 (API 24)+
> Media3 APIs are supported from API 21+, but testing is focused on API 28+.

> ℹ️ This library requires `compileSdkVersion = 35` and `targetSdkVersion = 35` to support the latest Media3 features and ensure compatibility with modern Android Studio tooling.
> If you're on older SDKs, we recommend upgrading to avoid build issues.

#### Gradle Configuration

In `android/build.gradle`:

```gradle
buildscript {
    ext {
        minSdkVersion = 24
        compileSdkVersion = 35
        targetSdkVersion = 35
        // ...
    }
}
```

## 📚 API Overview

### 🛠 Methods

- **load(track: AudioProTrack): void**
  - Loads the specified track without starting playback.
- **play(): void**
  - Starts playing the loaded track.
- **pause(): void**
  - Pauses the current playback.
- **resume(): void**
  - Resumes playback if paused.
- **stop(): void**
  - Stops the playback, resetting to position 0 and clearing the playing track.
- **seekTo(positionMs: number): void**
  - Seeks to a specific position (in milliseconds).
- **seekForward(amountMs?: number): void**
  - Seeks forward (default 30 seconds).
- **seekBack(amountMs?: number): void**
  - Seeks backward (default 30 seconds).
- **configure(options: AudioProSetupOptions): void**
  - Optional. Sets playback options like content type (`'music'` or `'speech'`). Takes effect the next time `play()` is called.
- **getTimings(): { position: number, duration: number }**
  - Returns the current playback position and total duration in milliseconds.
- **getState(): AudioProState**
  - Returns the current playback state (STOPPED, LOADING, PLAYING, PAUSED).
- **getTrack(): AudioProTrack | undefined**
  - Returns the currently playing track, or undefined if no track is playing.
- **setPlaybackSpeed(speed: number): void**
  - Sets the playback speed rate (0.25 to 2.0). Normal speed is 1.0.
- **getPlaybackSpeed(): number**
  - Returns the current playback speed rate.

### 🎧 Event Listeners

- **addListener(callback: AudioProEventCallback): EmitterSubscription**
  - Listens for playback events (e.g., track ended, errors, progress).

### 🧱 Enums

- **AudioProState:** `STOPPED`, `LOADING`, `PLAYING`, `PAUSED`
- **AudioProEvent:** `TRACK_ENDED`, `PLAYBACK_ERROR`, `PROGRESS`, `SEEK_COMPLETE`, `REMOTE_NEXT`, `REMOTE_PREV`

### Lock Screen Controls

Both iOS and Android support lock screen and notification controls for play/pause, seek, and track navigation (next/previous). To handle next and previous track events:

```typescript
import { AudioPro, AudioProEventName } from 'react-native-audio-pro';

AudioPro.addEventListener((event) => {
  if (event.name === AudioProEventName.REMOTE_NEXT) {
    // Handle next track button press
    console.log('User pressed Next button');
    // The current track is included in the event payload
    console.log('Current track:', event.track);
    // Load and play next track
  }

  if (event.name === AudioProEventName.REMOTE_PREV) {
    // Handle previous track button press
    console.log('User pressed Previous button');
    // The current track is included in the event payload
    console.log('Current track:', event.track);
    // Load and play previous track
  }
});
```

### 🧩 Types

```typescript
type AudioProTrack = {
    id: string;
    url: string; // the media url (mp3, m4a)
    title: string;
    artwork: string; // the image url (jpg, png)
    album?: string;
    artist?: string;
};

type AudioProSetupOptions = {
    contentType?: 'music' | 'speech';
    debug?: boolean; // Verbose logging
};

// All event payloads include the current track (null when no track is playing)
type AudioProEventPayload = {
    name: AudioProEventName;
    track: AudioProTrack | null;
    // Additional properties based on event type
    position?: number;
    duration?: number;
    error?: string;
    errorCode?: number;
};
```

### About contentType

Use `'speech'` for podcasts or audiobooks, `'music'` for songs or music-heavy audio. This optimizes playback behavior like audio focus and routing. Defaults to `'music'`.

## ⚡️ useAudioPro Hook Example

The `useAudioPro` hook gives you real-time access to the playback state, current position, total duration, and the currently playing track.

```typescript jsx
import { useAudioPro } from 'react-native-audio-pro';

const AudioStatus = () => {
  const { state, position, duration, track, playbackSpeed } = useAudioPro();

  return (
    <View>
      <Text>Playback State: {state}</Text>
      <Text>Current Position: {position}ms</Text>
      <Text>Total Duration: {duration}ms</Text>
      <Text>Playback Speed: {playbackSpeed}x</Text>
      {track && (
        <View>
          <Text>Track ID: {track.id}</Text>
          <Text>Now Playing: {track.title}</Text>
          <Text>Artist: {track.artist}</Text>
        </View>
      )}
    </View>
  );
};

export default AudioStatus;
```

## 📦 API Usage Example

```typescript
// Optional: Set playback config
AudioPro.configure({ contentType: 'music', debug: __DEV__ });

// Define an audio track
const track = {
  id: 'track-001',
  url: 'https://example.com/audio.mp3',
  title: 'My Track',
  artwork: 'https://example.com/artwork.jpg',
  artist: 'Artist Name',
};

// Load and play the track
AudioPro.load(track);
AudioPro.play(track);

// Control playback
AudioPro.pause();
AudioPro.resume();
AudioPro.seekTo(60);

// Adjust playback speed (1.0 is normal speed)
AudioPro.setPlaybackSpeed(1.5); // 1.5x speed for faster playback
AudioPro.setPlaybackSpeed(0.8); // 0.8x speed for slower playback

// Get current state without using the hook
const { position, duration } = AudioPro.getTimings();
const state = AudioPro.getState();
const track = AudioPro.getTrack();
const speed = AudioPro.getPlaybackSpeed();
console.log(`Currently playing: ${track?.title} (${position}/${duration}ms) - State: ${state} - Speed: ${speed}x`);

// Listen for player events
const eventSubscription = AudioPro.addEventListener((event: AudioProEventPayload) => {
  // const {name, position, duration} = event;
  console.log('AudioPro Event:', event);
});
```

## 📱 Example App

A complete working example is provided in the [`example/`](./example) folder.

It demonstrates how to use `react-native-audio-pro` in a real React Native app, including:

- Track metadata (title, artist, artwork)
- Play/Pause/Seek/Skip controls
- Progress slider
- Event listener for events

### To run the example:

* Clone this repo and run the below commands

```bash
yarn install
yarn example start
# In a new terminal:
yarn example android
yarn example ios
```

**OR** open the `./example/ios` folder in XCode, or the `./example/android` folder in Android Studio and run in a simulator or physical device.

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
