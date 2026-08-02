import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Streams raw PCM chunks through a Web Audio `AudioContext`.
///
/// Fed chunks become `AudioBuffer`s scheduled back-to-back on the context
/// timeline, which plays gaplessly. Each buffer carries the stream's sample
/// rate, so the browser resamples to the hardware rate. Pause and resume map
/// to suspending and resuming the context, which freezes the timeline –
/// scheduled buffers survive a pause untouched.
///
/// Mirrors the event contract of the Android/Darwin backends: `state`,
/// `underrun` (once per starvation gap) and `drained` events, and a
/// buffered-duration gauge counted in whole chunks.
class WebPcmPlayer {
  /// Creates a player and its backing `AudioContext`, initially suspended.
  ///
  /// Throws if the browser rejects [sampleRate] – the Web Audio spec only
  /// guarantees 8000-96000 Hz, though most browsers accept a wider range.
  WebPcmPlayer({
    required this.sampleRate,
    required this.channels,
    required this.isFloat,
    required void Function(Map<String, Object?> event) emit,
  }) : _emit = emit {
    // Probe the rate up front so create() fails fast instead of every feed()
    // failing later.
    _ctx.createBuffer(channels, 1, sampleRate);
    _gain = _ctx.createGain();
    _gain.connect(_ctx.destination);
    // A fresh context may already be running if the page has had a user
    // gesture; playback must not start before play().
    _settle(_ctx.suspend());
  }

  /// Sample rate of the fed PCM data, in hertz.
  final int sampleRate;

  /// Number of interleaved channels in the fed PCM data.
  final int channels;

  /// Whether samples are f32le (true) or s16le (false).
  final bool isFloat;

  final void Function(Map<String, Object?> event) _emit;

  final web.AudioContext _ctx = web.AudioContext();
  late final web.GainNode _gain;
  final Set<web.AudioBufferSourceNode> _sources = {};

  bool _playing = false;
  bool _paused = false;
  bool _eosPending = false;
  bool _underrunReported = false;
  bool _closed = false;
  int _framesScheduled = 0;
  int _framesCompleted = 0;
  int _buffersPending = 0;
  double _nextTime = 0;
  // Bumped on stop/dispose so ended events from cleared sources are ignored.
  int _generation = 0;

  /// Converts a chunk to an `AudioBuffer` and schedules it after the last one.
  void feed(Uint8List bytes) {
    _underrunReported = false;
    final frames = bytes.length ~/ (channels * (isFloat ? 4 : 2));
    if (frames == 0) return;
    final samples = _toFloat32(bytes, frames * channels);
    final buffer = _ctx.createBuffer(channels, frames, sampleRate);
    for (var ch = 0; ch < channels; ch++) {
      var channelData = samples;
      if (channels > 1) {
        channelData = Float32List(frames);
        for (var f = 0; f < frames; f++) {
          channelData[f] = samples[f * channels + ch];
        }
      }
      buffer.copyToChannel(channelData.toJS, ch);
    }
    final source = _ctx.createBufferSource()..buffer = buffer;
    source.connect(_gain);
    final now = _ctx.currentTime;
    final startTime = _nextTime > now ? _nextTime : now;
    _nextTime = startTime + frames / sampleRate;
    _buffersPending++;
    _framesScheduled += frames;
    _sources.add(source);
    final generation = _generation;
    source.addEventListener(
      'ended',
      ((web.Event _) {
        _sources.remove(source);
        source.disconnect();
        _bufferPlayedBack(frames, generation);
      }).toJS,
    );
    source.start(startTime);
  }

  /// Starts or resumes the context clock.
  ///
  /// The browser may hold the returned resume promise until the page's first
  /// user gesture; state is reported as playing immediately, matching the
  /// other backends.
  void play() {
    if (_playing && !_paused) return;
    _playing = true;
    _paused = false;
    _settle(_ctx.resume());
    _emit({'event': 'state', 'state': 'playing'});
  }

  /// Suspends the context clock, freezing scheduled buffers in place.
  void pause() {
    if (!_playing || _paused) return;
    _paused = true;
    _settle(_ctx.suspend());
    _emit({'event': 'state', 'state': 'paused'});
  }

  /// Stops playback and discards all scheduled buffers.
  void stop() {
    final wasActive = _playing;
    _reset();
    if (wasActive) _emit({'event': 'state', 'state': 'idle'});
  }

  /// Marks the stream complete; drains once the last buffer finishes.
  void endOfStream() {
    _eosPending = true;
    if (_buffersPending == 0) _drain();
  }

  /// Sets output gain, 0.0-1.0.
  void setVolume(double volume) {
    _gain.gain.value = volume;
  }

  /// Microseconds of fed audio not yet played.
  int bufferedDurationMicros() {
    // Whole-chunk based: overestimates by the not-yet-finished part of the
    // currently playing chunk, matching the other backends' gauges.
    final frames = _framesScheduled - _framesCompleted;
    return frames <= 0 ? 0 : frames * 1000000 ~/ sampleRate;
  }

  /// Discards all state and closes the `AudioContext`.
  void release() {
    _reset();
    _closed = true;
    _settle(_ctx.close());
  }

  void _reset() {
    _generation++;
    for (final source in _sources) {
      try {
        source.stop();
      } catch (_) {
        // stop() on an already-ended source throws on some browsers.
      }
      source.disconnect();
    }
    _sources.clear();
    _playing = false;
    _paused = false;
    _eosPending = false;
    _underrunReported = false;
    _framesScheduled = 0;
    _framesCompleted = 0;
    _buffersPending = 0;
    _nextTime = 0;
    if (!_closed) _settle(_ctx.suspend());
  }

  void _bufferPlayedBack(int frames, int generation) {
    if (generation != _generation) return;
    _framesCompleted += frames;
    _buffersPending--;
    if (_buffersPending > 0) return;
    if (_eosPending) {
      _drain();
    } else if (_playing && !_paused && !_underrunReported) {
      _underrunReported = true;
      _emit({'event': 'underrun'});
    }
  }

  void _drain() {
    final wasActive = _playing;
    _reset();
    if (wasActive) _emit({'event': 'state', 'state': 'idle'});
    _emit({'event': 'drained'});
  }

  /// Converts interleaved little-endian PCM bytes to float samples.
  ///
  /// Web targets are always little-endian, so typed-data views read the wire
  /// format directly; a misaligned view (the codec hands out views into the
  /// message buffer) is realigned with a copy first.
  Float32List _toFloat32(Uint8List bytes, int count) {
    if (isFloat) {
      final data =
          bytes.offsetInBytes % 4 == 0 ? bytes : Uint8List.fromList(bytes);
      return Float32List.view(data.buffer, data.offsetInBytes, count);
    }
    final data = bytes.offsetInBytes.isEven ? bytes : Uint8List.fromList(bytes);
    final ints = Int16List.view(data.buffer, data.offsetInBytes, count);
    final floats = Float32List(count);
    for (var i = 0; i < count; i++) {
      floats[i] = ints[i] / 32768;
    }
    return floats;
  }

  /// Detaches suspend/resume/close promises: results are irrelevant and
  /// rejections (e.g. resume() before the first user gesture on Safari) must
  /// not surface as unhandled errors.
  void _settle(JSPromise<JSAny?> promise) {
    promise.toDart.then((_) {}, onError: (_) {});
  }
}
