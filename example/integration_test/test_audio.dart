import 'dart:math';
import 'dart:typed_data';

/// A mono s16le sine tone with a fade in and out, so test audio never clicks.
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
