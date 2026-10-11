# audio_stream_player example

Simulates a streaming TTS API end-to-end: synthesizes a robot-voice
utterance and feeds it to `AudioStreamPlayer` in ~100ms chunks with
network-like jitter, including occasional hiccups that demonstrate underrun
recovery.

```sh
flutter run
```

Watch the buffer gauge fill as chunks arrive and drain as they play; the
log shows state transitions, underruns, and the `endOfStream()` drain.

## OpenAI TTS demo

This alternate app streams a real HTTP response into `AudioStreamPlayer`,
then waits for the last sample to play. Stop closes the HTTP client and
flushes the player. The local Python proxy requests raw PCM: 24 kHz,
mono, signed 16-bit little-endian, with no WAV header.
See the [OpenAI speech documentation](https://developers.openai.com/api/docs/guides/text-to-speech).

From the `example` directory, start the proxy in one terminal:

```sh
# Set OPENAI_API_KEY in this terminal's environment first.
python3 tool/tts_proxy.py
```

Each tap on Speak makes a paid OpenAI speech request. To try the HTTP
streaming path without an API key or API calls, use:

```sh
python3 tool/tts_proxy.py --fixture
```

In another terminal, run the demo in Chrome and tap Speak:

```sh
flutter pub get
flutter run -d chrome -t lib/tts_main.dart
```

The proxy uses only Python's standard library and binds to loopback for
local development. Keep API keys on your backend when adapting it for
production; add your application's authentication there. Serve raw PCM
with the player's sample rate and encoding, and stream the response
without buffering the full utterance.

`TTS_URL` selects a different streaming endpoint:

```sh
flutter run -d chrome -t lib/tts_main.dart \
  --dart-define=TTS_URL=https://your-backend.example/speech
```

The player also works on Android, iOS and macOS. Native apps need the
platform's network permissions/entitlements and, for a local HTTP proxy,
development cleartext exceptions. An Android emulator reaches the host
at `10.0.2.2` rather than `127.0.0.1`; physical devices need a reachable
backend URL. The commands above use Chrome so no native network setup
is needed.
