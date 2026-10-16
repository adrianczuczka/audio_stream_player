# Changelog

## 1.2.0

- Added `AudioSessionConfig` and the `audioSession` parameter of
  `AudioStreamPlayer.create`. `AudioSessionConfig.voiceChat` uses the iOS
  `.playAndRecord` category with `.voiceChat` mode, `.defaultToSpeaker` and
  `.allowBluetooth`, so realtime voice apps can record the microphone while
  the player plays. `AudioSessionConfig.manual` leaves the session to you.
- Deprecated `configureAudioSession`. Use
  `audioSession: AudioSessionConfig.manual` instead of
  `configureAudioSession: false`.
- iOS: the audio session is now deactivated with
  `.notifyOthersOnDeactivation` about a second after every player is idle,
  so music from other apps resumes after an utterance. Idle engines are
  stopped first, on macOS too.
- iOS: audio session interruptions (phone calls, Siri) move a playing
  player to `paused` instead of leaving it silent while it reports
  `playing`. When the interruption ends with `.shouldResume`, the player
  resumes by itself.
- iOS and macOS: the player restarts `AVAudioEngine` after a configuration
  change, such as connecting AirPods mid-utterance. Before, playback went
  silent while the state stayed `playing`.
- Android: `play()` requests transient audio focus
  (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`), and focus is abandoned about a
  second after every player is idle. A transient focus loss pauses the
  player until focus returns; a permanent loss pauses it until you call
  `play()`. `play()` throws `audio_focus_denied` if the system refuses
  focus.
- Fixed a native leak on hot restart: players from the previous run kept
  their `AVAudioEngine` or `AudioTrack` and writer thread, and kept playing.
  They're now released when the restarted app creates its first player.
- Fixed native error events, such as an `AudioTrack` write error, being
  dropped instead of delivered as errors on `onStateChanged`.

## 1.1.0

- Added web support: playback through the Web Audio API, with the same
  gapless scheduling, underrun events, `endOfStream()` drain future and
  buffered-duration gauge as the mobile/desktop backends.
- Web notes: browsers only start audio after a user gesture, so make the
  first `play()` call from an input handler; sample rates are guaranteed
  for 8000-96000 Hz (most browsers accept more).

## 1.0.3

- Re-recorded the demo GIF with the animated wave buffer gauge, so the
  pub.dev screenshot matches the current example app.
- No functional changes.

## 1.0.2

- Added a demo GIF of the example app to the README and package screenshots.
- No functional changes.

## 1.0.1

- Shortened the package description to meet pub.dev's 180-character limit.
- No functional changes.

## 1.0.0

Complete rewrite. `audio_stream_player` is now a low-latency raw PCM
streaming player for feeding audio chunks from TTS and realtime voice APIs.

- Feed `Uint8List` PCM chunks (`s16le` or `f32le`, mono or stereo, any
  sample rate) and hear them as they arrive.
- `endOfStream()` future that completes when the last sample has played.
- Underrun events, buffered-duration introspection, pause/resume/stop,
  per-player volume, multiple concurrent players.
- Platforms: Android (`AudioTrack`), iOS and macOS (`AVAudioEngine`, shared
  Darwin source, CocoaPods + Swift Package Manager).

The 0.0.1 URL-playback API from 2018 has been removed entirely.
