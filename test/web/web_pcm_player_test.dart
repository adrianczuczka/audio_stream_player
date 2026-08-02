@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:audio_stream_player/src/web_pcm_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// Exercises the Web Audio backend in a real browser: buffer accounting,
/// state events, the interop calls themselves, and real-time playback
/// (the test runner launches Chrome with autoplay allowed, so the context
/// clock actually runs).
void main() {
  Uint8List silence(int frames, {int channels = 1, int bytesPerSample = 2}) =>
      Uint8List(frames * channels * bytesPerSample);

  test('tracks buffered duration in whole fed chunks', () {
    final player = WebPcmPlayer(
        sampleRate: 24000, channels: 1, isFloat: false, emit: (_) {});
    player.feed(silence(2400));
    player.feed(silence(1200));
    expect(player.bufferedDurationMicros(), 150000);
    player.release();
  });

  test('counts frames, not bytes, for f32 stereo', () {
    final player = WebPcmPlayer(
        sampleRate: 48000, channels: 2, isFloat: true, emit: (_) {});
    player.feed(silence(48, channels: 2, bytesPerSample: 4));
    expect(player.bufferedDurationMicros(), 1000);
    player.release();
  });

  test('play, stop and empty-buffer drain emit backend events', () {
    final events = <Map<String, Object?>>[];
    final player = WebPcmPlayer(
        sampleRate: 24000, channels: 1, isFloat: false, emit: events.add);

    player.play();
    player.feed(silence(2400));
    player.stop();
    expect(player.bufferedDurationMicros(), 0);
    expect(events, [
      {'event': 'state', 'state': 'playing'},
      {'event': 'state', 'state': 'idle'},
    ]);

    events.clear();
    player.play();
    player.endOfStream();
    expect(events, [
      {'event': 'state', 'state': 'playing'},
      {'event': 'state', 'state': 'idle'},
      {'event': 'drained'},
    ]);
    player.release();
  });

  test('ignores a trailing partial frame', () {
    final player = WebPcmPlayer(
        sampleRate: 24000, channels: 1, isFloat: false, emit: (_) {});
    player.feed(Uint8List(3));
    expect(player.bufferedDurationMicros(), 41); // 1 frame of 24 kHz
    player.release();
  });

  test('plays out in real time: underrun on starvation, drain after eos',
      () async {
    // Default headless Chrome never advances AudioContext clocks (autoplay
    // policy, and no audio device pulling samples), which would hang this
    // test. Probe first and skip visibly when playback cannot run. To
    // exercise it locally, point CHROME_EXECUTABLE at a wrapper that adds
    // --autoplay-policy=no-user-gesture-required and drops --headless.
    final probe = web.AudioContext();
    probe.resume();
    var clockRuns = false;
    for (var i = 0; i < 15 && !clockRuns; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      clockRuns = probe.currentTime > 0;
    }
    probe.close();
    if (!clockRuns) {
      markTestSkipped('AudioContext clock frozen (headless Chrome); '
          'real-time playback cannot be exercised here');
      return;
    }

    final events = <Map<String, Object?>>[];
    final player = WebPcmPlayer(
        sampleRate: 24000, channels: 1, isFloat: false, emit: events.add);
    Future<void> waitFor(String event) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!events.any((e) => e['event'] == event)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for $event; saw $events');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    player.play();
    player.feed(silence(7200)); // 300ms
    // The buffer must exhaust without endOfStream and report starvation.
    await waitFor('underrun');
    expect(player.bufferedDurationMicros(), 0);

    // Feeding again resumes; drain must take roughly the audio duration.
    events.clear();
    final stopwatch = Stopwatch()..start();
    player.feed(silence(12000)); // 500ms
    player.endOfStream();
    await waitFor('drained');
    stopwatch.stop();
    expect(stopwatch.elapsed, greaterThan(const Duration(milliseconds: 300)));
    expect(events, [
      {'event': 'state', 'state': 'idle'},
      {'event': 'drained'},
    ]);
    player.release();
  }, timeout: const Timeout(Duration(minutes: 1)));
}
