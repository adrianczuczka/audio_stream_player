import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_session_config.dart';
import 'pcm_format.dart';
import 'player_state.dart';

/// A player for raw PCM audio streams.
///
/// Designed for feeding audio as it arrives from a TTS or realtime voice API:
///
/// ```dart
/// final player = await AudioStreamPlayer.create(sampleRate: 24000);
/// await player.play();
/// await for (final chunk in ttsResponse) {
///   await player.feed(chunk);
/// }
/// await player.endOfStream(); // completes when the last sample has played
/// await player.dispose();
/// ```
///
/// Chunks may be any length — frame alignment across chunk boundaries is
/// handled internally. Buffering is unbounded; use [bufferedDuration] for
/// backpressure if the source can outrun playback indefinitely.
class AudioStreamPlayer {
  AudioStreamPlayer._({
    required int playerId,
    required this.sampleRate,
    required this.channels,
    required this.format,
  }) : _playerId = playerId;

  static const MethodChannel _methods =
      MethodChannel('audio_stream_player/methods');
  static int _nextPlayerId = 0;

  final int _playerId;

  /// Sample rate of the fed PCM data, in hertz.
  final int sampleRate;

  /// Number of interleaved channels in the fed PCM data.
  final int channels;

  /// Sample encoding of the fed PCM data.
  final PcmFormat format;

  final _stateController = StreamController<PlayerState>.broadcast();
  final _underrunController = StreamController<void>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  PlayerState _state = PlayerState.idle;
  Completer<void>? _drainCompleter;
  Uint8List _carry = Uint8List(0);
  bool _eosPending = false;
  bool _disposed = false;

  int get _frameBytes => channels * format.bytesPerSample;

  /// Creates a player for a PCM stream with the given properties.
  ///
  /// [sampleRate] and [channels] describe the data you will [feed] — they do
  /// not need to match the device's output; resampling is handled natively.
  ///
  /// [audioSession] controls the iOS audio session and Android audio focus.
  /// The default, [AudioSessionConfig.playback], suits TTS playback. Realtime
  /// voice apps that record the microphone while the player plays need
  /// [AudioSessionConfig.voiceChat] on iOS. Pass [AudioSessionConfig.manual]
  /// if you manage the session yourself, for example with the
  /// `audio_session` package.
  ///
  /// Passing `configureAudioSession: false` is equivalent to
  /// `audioSession: AudioSessionConfig.manual`.
  static Future<AudioStreamPlayer> create({
    required int sampleRate,
    int channels = 1,
    PcmFormat format = PcmFormat.s16le,
    AudioSessionConfig audioSession = AudioSessionConfig.playback,
    @Deprecated('Use audioSession: AudioSessionConfig.manual instead. '
        'This parameter will be removed in 2.0.0.')
    bool configureAudioSession = true,
  }) async {
    if (sampleRate < 4000 || sampleRate > 384000) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
    if (channels < 1 || channels > 2) {
      throw ArgumentError.value(channels, 'channels', 'must be 1 or 2');
    }
    final playerId = _nextPlayerId++;
    await _methods.invokeMethod<void>('create', {
      'playerId': playerId,
      'sampleRate': sampleRate,
      'channels': channels,
      'format': format.name,
      'audioSession':
          (configureAudioSession ? audioSession : AudioSessionConfig.manual)
              .name,
    });
    final player = AudioStreamPlayer._(
      playerId: playerId,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
    );
    player._listenToEvents();
    return player;
  }

  /// The current playback state.
  PlayerState get state => _state;

  /// Playback state changes.
  ///
  /// Platform errors reported outside of a method call are delivered as
  /// errors on this stream.
  Stream<PlayerState> get onStateChanged => _stateController.stream;

  /// Fires when the player runs out of buffered audio while [PlayerState.playing].
  ///
  /// Playback continues automatically when more data is fed; this event is
  /// for showing buffering UI or tuning chunk delivery. Not fired for the
  /// expected buffer exhaustion after [endOfStream].
  Stream<void> get onUnderrun => _underrunController.stream;

  /// Appends a chunk of PCM bytes to the playback buffer.
  ///
  /// [chunk] must match the [format], [sampleRate] and [channels] the player
  /// was created with. Chunks may split frames at any byte boundary; a
  /// trailing partial frame is held back and prepended to the next chunk.
  ///
  /// Throws [StateError] if called between [endOfStream] and its completion.
  Future<void> feed(Uint8List chunk) async {
    _checkNotDisposed();
    if (_eosPending) {
      throw StateError(
          'Cannot feed after endOfStream() until the stream drains');
    }
    Uint8List data;
    if (_carry.isEmpty) {
      data = chunk;
    } else {
      data = Uint8List(_carry.length + chunk.length)
        ..setAll(0, _carry)
        ..setAll(_carry.length, chunk);
    }
    final alignedLength = data.length - (data.length % _frameBytes);
    _carry = Uint8List.sublistView(data, alignedLength);
    if (alignedLength == 0) return;
    await _methods.invokeMethod<void>('feed', {
      'playerId': _playerId,
      'data': Uint8List.sublistView(data, 0, alignedLength),
    });
  }

  /// Starts or resumes playback of buffered audio.
  ///
  /// Safe to call before the first [feed]; the player plays silence-free from
  /// the moment data arrives.
  ///
  /// Unless the player uses [AudioSessionConfig.manual], this activates the
  /// iOS audio session or requests Android audio focus. It throws a
  /// [PlatformException] if the system refuses, for example during a phone
  /// call.
  ///
  /// On web, browsers only allow audio to start after a user gesture – make
  /// the first call from an input handler.
  Future<void> play() async {
    _checkNotDisposed();
    await _methods.invokeMethod<void>('play', {'playerId': _playerId});
  }

  /// Pauses playback, retaining buffered audio.
  Future<void> pause() async {
    _checkNotDisposed();
    await _methods.invokeMethod<void>('pause', {'playerId': _playerId});
  }

  /// Stops playback and discards all buffered audio.
  ///
  /// A pending [endOfStream] future completes (its audio will never play).
  Future<void> stop() async {
    _checkNotDisposed();
    _carry = Uint8List(0);
    _eosPending = false;
    await _methods.invokeMethod<void>('stop', {'playerId': _playerId});
    _completeDrain();
  }

  /// Sets playback volume, from 0.0 (silent) to 1.0 (full).
  Future<void> setVolume(double volume) async {
    _checkNotDisposed();
    await _methods.invokeMethod<void>('setVolume', {
      'playerId': _playerId,
      'volume': volume.clamp(0.0, 1.0),
    });
  }

  /// How much fed audio is buffered but not yet played.
  Future<Duration> bufferedDuration() async {
    _checkNotDisposed();
    final micros = await _methods
        .invokeMethod<int>('bufferedDurationMicros', {'playerId': _playerId});
    return Duration(microseconds: micros ?? 0);
  }

  /// Signals that no more chunks will be fed for the current stream.
  ///
  /// Returns a future that completes when every buffered sample has been
  /// played (or the player is stopped first). After completion the player is
  /// [PlayerState.idle] and can be fed a new stream.
  ///
  /// A held-back partial frame from an unaligned final chunk is discarded.
  Future<void> endOfStream() async {
    _checkNotDisposed();
    if (_eosPending) return _drainCompleter!.future;
    _carry = Uint8List(0);
    _eosPending = true;
    _drainCompleter = Completer<void>();
    final future = _drainCompleter!.future;
    await _methods.invokeMethod<void>('endOfStream', {'playerId': _playerId});
    return future;
  }

  /// Releases native resources. The player cannot be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _completeDrain();
    await _eventSubscription?.cancel();
    await _methods.invokeMethod<void>('dispose', {'playerId': _playerId});
    await _stateController.close();
    await _underrunController.close();
  }

  void _listenToEvents() {
    final events = EventChannel('audio_stream_player/events/$_playerId');
    _eventSubscription = events.receiveBroadcastStream().listen(
      (dynamic event) {
        final map = event as Map<dynamic, dynamic>;
        switch (map['event'] as String) {
          case 'state':
            final state = PlayerState.values.byName(map['state'] as String);
            _state = state;
            _stateController.add(state);
          case 'underrun':
            _underrunController.add(null);
          case 'drained':
            _eosPending = false;
            _completeDrain();
          case 'error':
            if (!_stateController.isClosed) {
              _stateController.addError(PlatformException(
                code: 'audio_stream_player',
                message: map['message'] as String?,
              ));
            }
        }
      },
      onError: (Object error) {
        if (!_stateController.isClosed) _stateController.addError(error);
      },
    );
  }

  void _completeDrain() {
    _eosPending = false;
    final completer = _drainCompleter;
    _drainCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('AudioStreamPlayer has been disposed');
    }
  }

  /// The method channel used to talk to the native side, exposed for tests.
  @visibleForTesting
  static MethodChannel get methodChannel => _methods;
}
