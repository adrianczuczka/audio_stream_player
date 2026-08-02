# Changelog

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
