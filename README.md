# audio_stream_player

A low-latency raw PCM streaming player for Flutter. Feed audio byte chunks
from a TTS or realtime voice API and hear them as they arrive — no files, no
URLs, no waiting for the full response.

```dart
final player = await AudioStreamPlayer.create(sampleRate: 24000);
await player.play();

await for (final chunk in ttsApi.streamAudio(text)) {
  await player.feed(chunk); // Uint8List of s16le PCM
}

await player.endOfStream(); // completes when the last sample has played
```

## Why this package

General-purpose players (`just_audio`, `audioplayers`) are built around URLs
and files; wiring a live byte stream into them is awkward. This package does
one thing: gapless playback of PCM chunks as they arrive, with the lifecycle
hooks a streaming voice app actually needs:

- **Any stream rate** — feed 22.05/24/44.1 kHz mono straight from the API;
  resampling to the hardware rate is native.
- **Chunk-boundary safe** — chunks can split a sample frame anywhere; the
  remainder is carried automatically.
- **`endOfStream()` future** — know exactly when the utterance finished
  playing (for "speaking" indicators, turn-taking, barge-in).
- **Underrun events + buffered duration** — show buffering UI, tune your
  chunk delivery, or implement backpressure.
- **Pause / resume / stop-and-flush** — interrupt an utterance cleanly.
- **Multiple concurrent players** — TTS voice and sound effects side by side.

| Platform | Backend | Minimum |
| --- | --- | --- |
| Android | `AudioTrack` (low-latency mode) | API 21 |
| iOS | `AVAudioEngine` | 13.0 |
| macOS | `AVAudioEngine` | 10.15 |

## Usage

### Create a player

```dart
final player = await AudioStreamPlayer.create(
  sampleRate: 24000,          // rate of the bytes you feed
  channels: 1,                // 1 or 2, interleaved
  format: PcmFormat.s16le,    // or PcmFormat.f32le
);
```

On iOS the audio session is configured for playback automatically. If you
manage the session yourself (e.g. with `audio_session`), pass
`configureAudioSession: false`.

### Stream an utterance

```dart
await player.play();                  // safe before any data arrives
await for (final chunk in source) {
  await player.feed(chunk);
}
await player.endOfStream();           // resolves after the last sample plays
```

After the drain the player returns to `PlayerState.idle` and can be fed the
next utterance.

### Observe playback

```dart
player.onStateChanged.listen((s) => ...);   // idle / playing / paused
player.onUnderrun.listen((_) => ...);       // buffer starved mid-stream
final buffered = await player.bufferedDuration();
```

An underrun is not an error — playback resumes by itself when the next chunk
arrives. Use it to decide whether to delay `play()` until you have some
audio buffered.

### Interrupt

```dart
await player.pause();  // keeps buffered audio, resume with play()
await player.stop();   // discards buffered audio, back to idle
```

`stop()` is the barge-in primitive: call it when the user starts talking
over the assistant.

### Clean up

```dart
await player.dispose();
```

## Notes

- Buffering is unbounded: if your source can outrun playback for minutes,
  poll `bufferedDuration()` and throttle your reads.
- Bytes are interleaved little-endian PCM, the wire format of essentially
  every TTS API. `PcmFormat.s16le` matches OpenAI, ElevenLabs, Cartesia,
  Google, and Amazon defaults.
- The example app simulates a jittery TTS byte stream end-to-end, including
  underrun recovery — `cd example && flutter run`.
