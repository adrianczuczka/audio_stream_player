import 'dart:async';

import 'package:flutter/services.dart';

enum PlayerState {
  STOPPED,
  PLAYING,
  PAUSED,
}

class AudioStreamPlayer {
  static const MethodChannel _channel =
      const MethodChannel('audio_stream_player');

  final StreamController<PlayerState> _playerStateController =
  new StreamController.broadcast();

  PlayerState _state = PlayerState.STOPPED;

  AudioStreamPlayer() {
    _channel.setMethodCallHandler(_audioPlayerStateChange);
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  Future<void> play(String url) async =>
      await _channel.invokeMethod('play', {'url': url});

  Future<void> pause() async => await _channel.invokeMethod('pause');

  Future<void> stop() async => await _channel.invokeMethod('stop');

  Future<void> mute() async => await _channel.invokeMethod('mute');

  PlayerState get state => _state;

  Future<void> _audioPlayerStateChange(MethodCall call) async {
    switch (call.method) {
      case "audio.onStart":
        _state = PlayerState.PLAYING;
        _playerStateController.add(PlayerState.PLAYING);
        break;
      case "audio.onPause":
        _state = PlayerState.PAUSED;
        _playerStateController.add(PlayerState.PAUSED);
        break;
      case "audio.onStop":
        _state = PlayerState.STOPPED;
        _playerStateController.add(PlayerState.STOPPED);
        break;
      case "audio.onError":
        _state = PlayerState.STOPPED;
        _playerStateController.addError(call.arguments);
        break;
      default:
        throw new ArgumentError('Unknown method ${call.method} ');
    }
  }
}
