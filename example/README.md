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
