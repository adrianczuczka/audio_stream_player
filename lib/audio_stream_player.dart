import 'dart:async';

import 'package:flutter/services.dart';

class AudioStreamPlayer {
  static const MethodChannel _channel =
      const MethodChannel('audio_stream_player');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
