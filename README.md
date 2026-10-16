# audio_stream_player

[![pub package](https://img.shields.io/pub/v/audio_stream_player.svg)](https://pub.dev/packages/audio_stream_player)
[![CI](https://github.com/adrianczuczka/audio_stream_player/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/adrianczuczka/audio_stream_player/actions/workflows/ci.yml)

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

<img src="https://raw.githubusercontent.com/adrianczuczka/audio_stream_player/master/doc/demo.gif" width="320" alt="Example app streaming a jittery TTS-style byte stream, showing the buffer gauge and underrun recovery">

## Why this package

General-purpose players (`just_audio`, `audioplayers`) are built around URLs
and files; wiring a live byte stream into them is awkward. `flutter_pcm_sound`
and `flutter_sound` can play PCM streams — the former through a feed-me
callback (s16 only, one global player), the latter as part of a full
recorder/player suite. This package does one thing: gapless playback of PCM
chunks as they arrive, with the lifecycle hooks a streaming voice app
actually needs:

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
| Web | Web Audio (`AudioContext`) | Any modern browser |

## Installation

```sh
flutter pub add audio_stream_player
```

```dart
import 'package:audio_stream_player/audio_stream_player.dart';
```

[API reference](https://pub.dev/documentation/audio_stream_player/latest/)
· [Changelog](CHANGELOG.md)
· [GitHub releases](https://github.com/adrianczuczka/audio_stream_player/releases)

## Usage

### Create a player

```dart
final player = await AudioStreamPlayer.create(
  sampleRate: 24000,          // rate of the bytes you feed
  channels: 1,                // 1 or 2, interleaved
  format: PcmFormat.s16le,    // or PcmFormat.f32le
);
```

The player manages the iOS audio session and Android audio focus for you.
Pick the configuration that matches your app:

```dart
// TTS playback (the default): interrupts other apps' audio while speaking.
await AudioStreamPlayer.create(sampleRate: 24000);

// Realtime voice: plays while a recorder captures the microphone.
await AudioStreamPlayer.create(
  sampleRate: 24000,
  audioSession: AudioSessionConfig.voiceChat,
);

// You manage the session yourself, for example with `audio_session`.
await AudioStreamPlayer.create(
  sampleRate: 24000,
  audioSession: AudioSessionConfig.manual,
);
```

On iOS, the default `.playback` category stops microphone capture, so a
realtime voice app that records while the assistant speaks must use
`AudioSessionConfig.voiceChat` or `AudioSessionConfig.manual`.

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
- Other apps' audio: `play()` activates the iOS audio session or requests
  transient Android audio focus, which pauses music in other apps. About a
  second after every player is idle (drained or stopped), the session is
  deactivated or focus abandoned, and the other app's music resumes. A
  paused player keeps the session. `play()` throws a `PlatformException` if
  the system refuses, for example during a phone call.
- Interruptions: a phone call, Siri, or another app taking audio focus moves
  a playing player to `PlayerState.paused`. When the interruption is
  transient and the system says playback may continue (iOS `.shouldResume`,
  Android focus regained), the player resumes by itself, as Apple and
  Android recommend. Otherwise it stays paused until you call `play()`. An
  explicit `pause()` or `stop()` cancels the automatic resume. With
  `AudioSessionConfig.manual` nothing resumes automatically; on Android the
  player then ignores audio focus entirely.
- Route changes: connecting or disconnecting headphones, AirPods or a
  Bluetooth speaker mid-utterance stops `AVAudioEngine` on iOS and macOS.
  The player restarts it and keeps playing on the new route. If the restart
  fails, the player moves to `paused` and reports the error on
  `onStateChanged`.
- Hot restart: players created before a hot restart are released when the
  restarted app creates its first player, so they stop playing and free
  their native resources.
- Bytes are interleaved little-endian PCM, the wire format of essentially
  TTS APIs when raw PCM output is selected. Request PCM explicitly and
  match the provider's sample rate, channels and encoding; MP3, WAV headers
  and other encoded audio cannot be fed directly.
- On web, browsers block audio until the page has had a user gesture: make
  the first `play()` call from an input handler (a tap on your mic or send
  button is enough). Sample rates of 8000–96000 Hz are guaranteed by the Web
  Audio spec; most browsers accept a wider range. Each player holds an
  `AudioContext`, and some browsers cap concurrent contexts, so prefer a
  handful of players at most.
- The example app simulates a jittery TTS byte stream end-to-end, including
  underrun recovery — `cd example && flutter run`.

## Real TTS example

The [OpenAI TTS demo](example/README.md#openai-tts-demo) streams 24 kHz
mono `s16le` audio from a local proxy into the player. It includes
stop-and-flush, error handling and a drain notification. The API key stays
in the proxy environment. A fixture mode lets you try the same streaming
path without an API key.
