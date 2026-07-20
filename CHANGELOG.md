# Changelog

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
