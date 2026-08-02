/// Web implementation of `audio_stream_player`, backed by the Web Audio API.
///
/// Registered automatically by the Flutter web plugin registrant; not for
/// direct use.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web_pcm_player.dart';

/// Plugin entry point: routes method calls to per-id [WebPcmPlayer]s.
class AudioStreamPlayerWeb {
  AudioStreamPlayerWeb._(this._registrar);

  final Registrar _registrar;
  final Map<int, _PlayerEntry> _players = {};

  /// Called by the generated plugin registrant.
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'audio_stream_player/methods',
      const StandardMethodCodec(),
      registrar,
    );
    final instance = AudioStreamPlayerWeb._(registrar);
    channel.setMethodCallHandler(instance._handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    try {
      if (call.method == 'create') {
        _create(args);
        return null;
      }
      final playerId = args['playerId'];
      final entry = _players[playerId];
      if (entry == null) {
        throw PlatformException(
          code: 'not_found',
          message: 'No player with id $playerId',
        );
      }
      switch (call.method) {
        case 'feed':
          entry.player.feed(args['data']! as Uint8List);
        case 'play':
          entry.player.play();
        case 'pause':
          entry.player.pause();
        case 'stop':
          entry.player.stop();
        case 'endOfStream':
          entry.player.endOfStream();
        case 'setVolume':
          entry.player.setVolume(args['volume']! as double);
        case 'bufferedDurationMicros':
          return entry.player.bufferedDurationMicros();
        case 'dispose':
          entry.player.release();
          unawaited(entry.events.close());
          _players.remove(playerId);
        default:
          throw MissingPluginException('${call.method} not implemented on web');
      }
      return null;
    } on PlatformException {
      rethrow;
    } on MissingPluginException {
      rethrow;
    } catch (error) {
      throw PlatformException(code: 'audio_stream_player', message: '$error');
    }
  }

  void _create(Map<String, Object?> args) {
    final playerId = args['playerId']! as int;
    final events = StreamController<Map<String, Object?>>();
    PluginEventChannel<Map<String, Object?>>(
      'audio_stream_player/events/$playerId',
      const StandardMethodCodec(),
      _registrar,
    ).setController(events);
    // `configureAudioSession` has no web equivalent and is ignored.
    final player = WebPcmPlayer(
      sampleRate: args['sampleRate']! as int,
      channels: args['channels']! as int,
      isFloat: args['format'] == 'f32le',
      emit: (event) {
        if (!events.isClosed) events.add(event);
      },
    );
    _players[playerId] = _PlayerEntry(player, events);
  }
}

class _PlayerEntry {
  _PlayerEntry(this.player, this.events);

  final WebPcmPlayer player;
  final StreamController<Map<String, Object?>> events;
}
