import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'audio_stream_player example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const sampleRate = 24000;

  AudioStreamPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _underrunSub;
  Timer? _gaugeTimer;

  PlayerState _state = PlayerState.idle;
  Duration _buffered = Duration.zero;
  int _underruns = 0;
  double _volume = 1.0;
  bool _streaming = false;
  bool _simulateNetworkJitter = true;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _createPlayer();
  }

  Future<void> _createPlayer() async {
    final player = await AudioStreamPlayer.create(sampleRate: sampleRate);
    _stateSub = player.onStateChanged.listen((state) {
      setState(() => _state = state);
      _addLog('state → ${state.name}');
    });
    _underrunSub = player.onUnderrun.listen((_) {
      setState(() => _underruns++);
      _addLog('underrun (buffer starved)');
    });
    _gaugeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final p = _player;
      if (p == null) return;
      final buffered = await p.bufferedDuration();
      if (mounted) setState(() => _buffered = buffered);
    });
    setState(() => _player = player);
  }

  /// Feeds a synthesized utterance in small chunks with network-like jitter,
  /// exactly the way bytes trickle in from a streaming TTS API.
  Future<void> _streamUtterance() async {
    final player = _player;
    if (player == null || _streaming) return;
    setState(() => _streaming = true);
    _addLog('streaming utterance...');
    try {
      await player.play();
      final random = Random();
      for (final chunk in _synthesizeUtterance(random)) {
        await player.feed(chunk);
        if (_simulateNetworkJitter) {
          // Chunks carry ~100ms of audio but arrive every 60-140ms, with an
          // occasional 400ms hiccup that demonstrates underrun recovery.
          final hiccup = random.nextInt(10) == 0;
          await Future<void>.delayed(
            Duration(milliseconds: hiccup ? 400 : 60 + random.nextInt(80)),
          );
        }
        if (!_streaming) return; // stopped mid-stream
      }
      _addLog('end of stream, awaiting drain...');
      await player.endOfStream();
      _addLog('drained: utterance fully played');
    } finally {
      if (mounted) setState(() => _streaming = false);
    }
  }

  /// Robot-speech synthesis: pitched tone bursts with speech-like cadence,
  /// enveloped to avoid clicks, as ~100ms s16le chunks.
  Iterable<Uint8List> _synthesizeUtterance(Random random) sync* {
    const chunkFrames = sampleRate ~/ 10;
    final pentatonic = [220.0, 247.5, 277.2, 330.0, 370.0];
    final syllables = 6 + random.nextInt(6);
    final samples = <double>[];
    for (var s = 0; s < syllables; s++) {
      final f = pentatonic[random.nextInt(pentatonic.length)];
      final durMs = 120 + random.nextInt(180);
      final n = sampleRate * durMs ~/ 1000;
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final envelope = sin(pi * i / n); // smooth attack/decay
        final vibrato = 1 + 0.01 * sin(2 * pi * 6 * t);
        samples.add(
          0.5 *
              envelope *
              (sin(2 * pi * f * vibrato * t) +
                  0.4 * sin(2 * pi * 2 * f * t) +
                  0.15 * sin(2 * pi * 3 * f * t)),
        );
      }
      // Inter-syllable gap.
      samples.addAll(
        List.filled(sampleRate * (30 + random.nextInt(70)) ~/ 1000, 0.0),
      );
    }
    for (var offset = 0; offset < samples.length; offset += chunkFrames) {
      final end = min(offset + chunkFrames, samples.length);
      final bytes = ByteData(2 * (end - offset));
      for (var i = offset; i < end; i++) {
        bytes.setInt16(
          2 * (i - offset),
          (samples[i] * 32767).round(),
          Endian.little,
        );
      }
      yield bytes.buffer.asUint8List();
    }
  }

  Future<void> _stop() async {
    setState(() => _streaming = false);
    await _player?.stop();
  }

  void _addLog(String message) {
    setState(() {
      _log.insert(0, message);
      if (_log.length > 30) _log.removeLast();
    });
  }

  @override
  void dispose() {
    _gaugeTimer?.cancel();
    _stateSub?.cancel();
    _underrunSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      appBar: AppBar(title: const Text('audio_stream_player')),
      body: player == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(label: Text(_state.name)),
                      Text(
                        'buffered: '
                        '${(_buffered.inMilliseconds / 1000).toStringAsFixed(2)}s',
                      ),
                      Text('underruns: $_underruns'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: min(_buffered.inMilliseconds / 2000, 1),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _streaming ? null : _streamUtterance,
                          icon: const Icon(Icons.record_voice_over),
                          label: const Text('Stream utterance'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _state == PlayerState.playing
                            ? () => player.pause()
                            : _state == PlayerState.paused
                            ? () => player.play()
                            : null,
                        icon: Icon(
                          _state == PlayerState.playing
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _state == PlayerState.idle ? null : _stop,
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Simulate network jitter'),
                    value: _simulateNetworkJitter,
                    onChanged: (v) =>
                        setState(() => _simulateNetworkJitter = v),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.volume_up, size: 20),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          onChanged: (v) {
                            setState(() => _volume = v);
                            player.setVolume(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _log.length,
                      itemBuilder: (context, i) => Text(
                        _log[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
