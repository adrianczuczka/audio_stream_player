import 'dart:async';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  MockStreamHandlerEventSink? eventSink;

  Future<AudioStreamPlayer> createPlayer({
    int sampleRate = 24000,
    int channels = 1,
    PcmFormat format = PcmFormat.s16le,
  }) async {
    calls = [];
    messenger.setMockMethodCallHandler(AudioStreamPlayer.methodChannel,
        (call) async {
      calls.add(call);
      if (call.method == 'create') {
        // Register the event channel for the assigned player id before the
        // create future resolves, which is when the player subscribes.
        final playerId = (call.arguments as Map)['playerId'] as int;
        messenger.setMockStreamHandler(
          EventChannel('audio_stream_player/events/$playerId'),
          MockStreamHandler.inline(onListen: (arguments, sink) {
            eventSink = sink;
          }),
        );
      }
      if (call.method == 'bufferedDurationMicros') return 1500000;
      return null;
    });
    final player = await AudioStreamPlayer.create(
        sampleRate: sampleRate, channels: channels, format: format);
    await pumpEventQueue();
    return player;
  }

  Map<String, Object?> argsOf(MethodCall call) =>
      (call.arguments as Map).cast<String, Object?>();

  tearDown(() {
    messenger.setMockMethodCallHandler(AudioStreamPlayer.methodChannel, null);
    eventSink = null;
  });

  test('create passes stream configuration to the platform', () async {
    await createPlayer(sampleRate: 44100, channels: 2, format: PcmFormat.f32le);
    expect(calls.single.method, 'create');
    final args = argsOf(calls.single);
    expect(args['sampleRate'], 44100);
    expect(args['channels'], 2);
    expect(args['format'], 'f32le');
    expect(args['configureAudioSession'], true);
  });

  test('create rejects invalid configurations', () async {
    expect(
        () => AudioStreamPlayer.create(sampleRate: 100), throwsArgumentError);
    expect(() => AudioStreamPlayer.create(sampleRate: 24000, channels: 3),
        throwsArgumentError);
  });

  test('feed carries partial frames across chunk boundaries', () async {
    final player = await createPlayer(); // s16le mono: 2 bytes per frame
    await player.feed(Uint8List.fromList([1, 2, 3]));
    await player.feed(Uint8List.fromList([4, 5, 6]));

    final feeds = calls.where((c) => c.method == 'feed').toList();
    expect(feeds, hasLength(2));
    expect(argsOf(feeds[0])['data'], [1, 2]);
    // Byte 3 was held back and prepended to the second chunk.
    expect(argsOf(feeds[1])['data'], [3, 4, 5, 6]);
  });

  test('feed skips the platform call when nothing is aligned', () async {
    final player = await createPlayer();
    await player.feed(Uint8List.fromList([1]));
    expect(calls.where((c) => c.method == 'feed'), isEmpty);
  });

  test('endOfStream completes when the platform reports drained', () async {
    final player = await createPlayer();
    var drained = false;
    final future = player.endOfStream().then((_) => drained = true);
    await pumpEventQueue();
    expect(drained, false);
    eventSink!.success({'event': 'drained'});
    await future;
    expect(drained, true);
  });

  test('feed between endOfStream and drain throws', () async {
    final player = await createPlayer();
    unawaited(player.endOfStream());
    await pumpEventQueue();
    expect(() => player.feed(Uint8List(2)), throwsStateError);
    eventSink!.success({'event': 'drained'});
    await pumpEventQueue();
    // After the drain, feeding a new stream is allowed again.
    await player.feed(Uint8List(2));
  });

  test('stop completes a pending endOfStream', () async {
    final player = await createPlayer();
    final future = player.endOfStream();
    await pumpEventQueue();
    await player.stop();
    await future; // must not hang
  });

  test('state events update state and stream', () async {
    final player = await createPlayer();
    expect(player.state, PlayerState.idle);
    final states = <PlayerState>[];
    player.onStateChanged.listen(states.add);
    eventSink!.success({'event': 'state', 'state': 'playing'});
    eventSink!.success({'event': 'state', 'state': 'paused'});
    await pumpEventQueue();
    expect(states, [PlayerState.playing, PlayerState.paused]);
    expect(player.state, PlayerState.paused);
  });

  test('underrun events reach the stream', () async {
    final player = await createPlayer();
    var underruns = 0;
    player.onUnderrun.listen((_) => underruns++);
    eventSink!.success({'event': 'underrun'});
    await pumpEventQueue();
    expect(underruns, 1);
  });

  test('bufferedDuration converts platform micros', () async {
    final player = await createPlayer();
    expect(
        await player.bufferedDuration(), const Duration(microseconds: 1500000));
  });

  test('setVolume clamps to 0..1', () async {
    final player = await createPlayer();
    await player.setVolume(1.7);
    final call = calls.lastWhere((c) => c.method == 'setVolume');
    expect(argsOf(call)['volume'], 1.0);
  });

  test('disposed player rejects further use', () async {
    final player = await createPlayer();
    await player.dispose();
    expect(() => player.feed(Uint8List(2)), throwsStateError);
    expect(() => player.play(), throwsStateError);
    await player.dispose(); // second dispose is a no-op
  });
}
