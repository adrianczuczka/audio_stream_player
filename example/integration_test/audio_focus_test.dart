import 'dart:io';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_audio.dart';

/// Android audio focus handling. The example's MainActivity requests focus
/// on a separate listener, which takes it from the plugin the way another
/// app would.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const focus = MethodChannel('audio_stream_player_example/focus');
  // AudioManager focus gain types.
  const gain = 1;
  const gainTransient = 2;
  const gainTransientMayDuck = 3;
  const requestGranted = 1;

  Future<void> takeFocus(int gainType) async {
    final result = await focus.invokeMethod<int>('request', {'gain': gainType});
    expect(result, requestGranted);
  }

  Future<void> returnFocus() => focus.invokeMethod<void>('abandon');

  /// Runs [action] and waits for the player to reach [state].
  Future<void> expectTransition(
    AudioStreamPlayer player,
    PlayerState state,
    Future<void> Function() action,
  ) async {
    final reached = player.onStateChanged.firstWhere((s) => s == state);
    await action();
    await reached.timeout(const Duration(seconds: 3));
    expect(player.state, state);
  }

  Future<AudioStreamPlayer> playLongUtterance({
    AudioSessionConfig audioSession = AudioSessionConfig.playback,
  }) async {
    final player = await AudioStreamPlayer.create(
      sampleRate: 24000,
      audioSession: audioSession,
    );
    await player.play();
    await player.feed(sine(sampleRate: 24000, millis: 4000));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.state, PlayerState.playing);
    return player;
  }

  tearDown(returnFocus);

  final skip = !Platform.isAndroid;

  testWidgets('a transient focus loss pauses, and regaining focus resumes', (
    tester,
  ) async {
    final player = await playLongUtterance();
    await expectTransition(
      player,
      PlayerState.paused,
      () => takeFocus(gainTransient),
    );
    await expectTransition(player, PlayerState.playing, returnFocus);
    await player.stop();
    await player.dispose();
  }, skip: skip);

  testWidgets('a duckable focus loss pauses instead of ducking', (
    tester,
  ) async {
    final player = await playLongUtterance();
    await expectTransition(
      player,
      PlayerState.paused,
      () => takeFocus(gainTransientMayDuck),
    );
    await expectTransition(player, PlayerState.playing, returnFocus);
    await player.stop();
    await player.dispose();
  }, skip: skip);

  testWidgets('a permanent focus loss pauses until play()', (tester) async {
    final player = await playLongUtterance();
    await expectTransition(player, PlayerState.paused, () => takeFocus(gain));
    await returnFocus();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(player.state, PlayerState.paused);

    // play() requests focus again.
    await expectTransition(player, PlayerState.playing, player.play);
    await player.stop();
    await player.dispose();
  }, skip: skip);

  testWidgets('an explicit pause during a focus loss is kept on regain', (
    tester,
  ) async {
    final player = await playLongUtterance();
    await expectTransition(
      player,
      PlayerState.paused,
      () => takeFocus(gainTransient),
    );
    await player.pause();
    await returnFocus();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(player.state, PlayerState.paused);
    await player.stop();
    await player.dispose();
  }, skip: skip);

  testWidgets('AudioSessionConfig.manual ignores focus changes', (
    tester,
  ) async {
    final player = await playLongUtterance(
      audioSession: AudioSessionConfig.manual,
    );
    await takeFocus(gainTransient);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(player.state, PlayerState.playing);
    await player.stop();
    await player.dispose();
  }, skip: skip);
}
