import 'dart:async';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MaterialApp(home: TtsDemo()));

class TtsDemo extends StatefulWidget {
  const TtsDemo({super.key});

  @override
  State<TtsDemo> createState() => _TtsDemoState();
}

class _TtsDemoState extends State<TtsDemo> {
  AudioStreamPlayer? _player;
  http.Client? _client;
  String _status = 'Preparing player…';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final player = await AudioStreamPlayer.create(sampleRate: 24000);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _status = 'Ready';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Player error: $error');
    }
  }

  Future<void> _speak() async {
    final player = _player;
    if (player == null || _client != null) return;
    final client = http.Client();
    setState(() {
      _client = client;
      _status = 'Streaming…';
    });
    try {
      // Play before the network request so web audio starts from the tap.
      await player.play();
      const url = String.fromEnvironment(
        'TTS_URL',
        defaultValue: 'http://127.0.0.1:8765/speech',
      );
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw StateError('TTS server returned HTTP ${response.statusCode}');
      }
      await for (final chunk in response.stream) {
        if (!identical(_client, client)) return;
        await player.feed(Uint8List.fromList(chunk));
      }
      if (!identical(_client, client)) return;
      await player.endOfStream();
      if (mounted && identical(_client, client)) {
        setState(() => _status = 'Finished playing');
      }
    } catch (error) {
      if (mounted && identical(_client, client)) {
        await player.stop();
        if (mounted) setState(() => _status = 'TTS error: $error');
      }
    } finally {
      client.close();
      if (mounted && identical(_client, client)) {
        setState(() => _client = null);
      }
    }
  }

  Future<void> _stop() async {
    final client = _client;
    _client = null;
    client?.close();
    await _player?.stop();
    if (mounted) setState(() => _status = 'Stopped');
  }

  @override
  void dispose() {
    _client?.close();
    _client = null;
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Streaming TTS')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The voice in this demo is AI-generated. '
            'Fixture mode plays a test tone instead.',
          ),
          const SizedBox(height: 16),
          Text(_status),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _player != null && _client == null ? _speak : null,
            child: const Text('Speak'),
          ),
          TextButton(
            onPressed: _client != null ? _stop : null,
            child: const Text('Stop and flush'),
          ),
        ],
      ),
    ),
  );
}
