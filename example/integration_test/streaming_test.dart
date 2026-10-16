import 'dart:math';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end tests against the real native audio stack. Audio is played
/// through the device/simulator output; assertions are on lifecycle events
/// and timing, not on what is audible.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Uint8List sine({
    required int sampleRate,
    required int millis,
    double frequency = 440,
  }) {
    final frames = sampleRate * millis ~/ 1000;
    final bytes = ByteData(frames * 2);
    for (var i = 0; i < frames; i++) {
      final envelope = sin(pi * i / frames);
      final sample = 0.4 * envelope * sin(2 * pi * frequency * i / sampleRate);
      bytes.setInt16(i * 2, (sample * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  testWidgets('plays a chunked stream to completion and drains', (
    tester,
  ) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);
    final states = <PlayerState>[];
    player.onStateChanged.listen(states.add);

    await player.play();
    // Feed 1 second of audio in 10 chunks, one of them frame-misaligned.
    for (var i = 0; i < 10; i++) {
      final chunk = sine(
        sampleRate: 24000,
        millis: 100,
        frequency: 300.0 + i * 40,
      );
      await player.feed(i == 4 ? chunk.sublist(0, chunk.length - 1) : chunk);
      if (i == 4) {
        await player.feed(chunk.sublist(chunk.length - 1));
      }
    }

    final buffered = await player.bufferedDuration();
    expect(buffered, greaterThan(const Duration(milliseconds: 200)));

    final stopwatch = Stopwatch()..start();
    await player.endOfStream().timeout(const Duration(seconds: 10));
    stopwatch.stop();

    // The ~1s of audio must actually take time to play out, and drain must
    // land reasonably close to the audio duration.
    expect(stopwatch.elapsed, greaterThan(const Duration(milliseconds: 300)));
    expect(player.state, PlayerState.idle);
    expect(states, contains(PlayerState.playing));

    // The player is reusable for a second stream after draining.
    await player.play();
    await player.feed(sine(sampleRate: 24000, millis: 300));
    await player.endOfStream().timeout(const Duration(seconds: 5));
    expect(player.state, PlayerState.idle);

    await player.dispose();
  });

  testWidgets('reports underruns when starved', (tester) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);
    var underruns = 0;
    player.onUnderrun.listen((_) => underruns++);

    await player.play();
    await player.feed(sine(sampleRate: 24000, millis: 200));
    // Let the 200ms of audio run out and starve for a while.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(underruns, 1);

    // Playback recovers when data arrives again.
    await player.feed(sine(sampleRate: 24000, millis: 200));
    await player.endOfStream().timeout(const Duration(seconds: 5));
    await player.dispose();
  });

  testWidgets('pause holds the buffer, stop discards it', (tester) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);

    await player.play();
    await player.feed(sine(sampleRate: 24000, millis: 2000));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await player.pause();
    expect(player.state, PlayerState.paused);

    final heldWhilePaused = await player.bufferedDuration();
    expect(heldWhilePaused, greaterThan(const Duration(milliseconds: 500)));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Paused: the buffer must not shrink.
    final stillHeld = await player.bufferedDuration();
    expect((stillHeld - heldWhilePaused).inMilliseconds.abs(), lessThan(150));

    await player.play();
    expect(player.state, PlayerState.playing);

    await player.stop();
    expect(player.state, PlayerState.idle);
    expect(await player.bufferedDuration(), Duration.zero);

    await player.dispose();
  });

  testWidgets('endOfStream on an empty idle player completes immediately', (
    tester,
  ) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);
    await player.endOfStream().timeout(const Duration(seconds: 3));
    await player.dispose();
  });

  testWidgets('two players stream concurrently', (tester) async {
    final a = await AudioStreamPlayer.create(sampleRate: 24000);
    final b = await AudioStreamPlayer.create(sampleRate: 44100);

    await a.play();
    await b.play();
    await a.feed(sine(sampleRate: 24000, millis: 400, frequency: 330));
    await b.feed(sine(sampleRate: 44100, millis: 400, frequency: 550));

    await Future.wait([
      a.endOfStream().timeout(const Duration(seconds: 5)),
      b.endOfStream().timeout(const Duration(seconds: 5)),
    ]);

    await a.dispose();
    await b.dispose();
  });

  testWidgets('plays again after the idle engine stop and session release', (
    tester,
  ) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);
    await player.play();
    await player.feed(sine(sampleRate: 24000, millis: 200));
    await player.endOfStream().timeout(const Duration(seconds: 5));

    // After a second idle, the engine is stopped and the audio session (iOS)
    // or audio focus (Android) is released. Playback must come back.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await player.play();
    expect(player.state, PlayerState.playing);
    await player.feed(sine(sampleRate: 24000, millis: 300));
    final stopwatch = Stopwatch()..start();
    await player.endOfStream().timeout(const Duration(seconds: 5));
    expect(stopwatch.elapsed, greaterThan(const Duration(milliseconds: 100)));
    expect(player.state, PlayerState.idle);
    await player.dispose();
  });

  testWidgets('audio fed ahead of play survives the idle engine stop', (
    tester,
  ) async {
    final player = await AudioStreamPlayer.create(sampleRate: 24000);
    await player.feed(sine(sampleRate: 24000, millis: 400));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(
      await player.bufferedDuration(),
      greaterThan(const Duration(milliseconds: 300)),
    );
    await player.play();
    final stopwatch = Stopwatch()..start();
    await player.endOfStream().timeout(const Duration(seconds: 5));
    expect(stopwatch.elapsed, greaterThan(const Duration(milliseconds: 200)));
    await player.dispose();
  });

  for (final config in AudioSessionConfig.values) {
    testWidgets('plays with AudioSessionConfig.${config.name}', (tester) async {
      final player = await AudioStreamPlayer.create(
        sampleRate: 24000,
        audioSession: config,
      );
      await player.play();
      await player.feed(sine(sampleRate: 24000, millis: 300));
      await player.endOfStream().timeout(const Duration(seconds: 5));
      expect(player.state, PlayerState.idle);
      await player.dispose();
    });
  }

  // Hot restart resets the Dart player id counter while native players
  // survive. These drive the method channel directly with fixed ids to
  // simulate a new isolate reusing ids.
  group('hot restart', () {
    final channel = AudioStreamPlayer.methodChannel;
    Map<String, Object> createArgs(int id) => {
      'playerId': id,
      'sampleRate': 24000,
      'channels': 1,
      'format': 's16le',
      'audioSession': 'playback',
    };

    testWidgets('create with a reused id replaces the old player', (
      tester,
    ) async {
      const id = 900001;
      await channel.invokeMethod<void>('create', createArgs(id));
      await channel.invokeMethod<void>('feed', {
        'playerId': id,
        'data': sine(sampleRate: 24000, millis: 500),
      });
      expect(
        await channel.invokeMethod<int>('bufferedDurationMicros', {
          'playerId': id,
        }),
        greaterThan(0),
      );

      await channel.invokeMethod<void>('create', createArgs(id));
      // The fresh player has none of the old player's audio.
      expect(
        await channel.invokeMethod<int>('bufferedDurationMicros', {
          'playerId': id,
        }),
        0,
      );
      await channel.invokeMethod<void>('dispose', {'playerId': id});
    });

    testWidgets('create with id 0 releases every leftover player', (
      tester,
    ) async {
      const leftover = 900002;
      await channel.invokeMethod<void>('create', createArgs(leftover));
      await channel.invokeMethod<void>('play', {'playerId': leftover});
      await channel.invokeMethod<void>('feed', {
        'playerId': leftover,
        'data': sine(sampleRate: 24000, millis: 2000),
      });

      await channel.invokeMethod<void>('create', createArgs(0));
      await expectLater(
        channel.invokeMethod<int>('bufferedDurationMicros', {
          'playerId': leftover,
        }),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
      await channel.invokeMethod<void>('dispose', {'playerId': 0});
    });
  });
}
