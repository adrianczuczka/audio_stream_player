/// Sample encoding of the PCM bytes fed to an `AudioStreamPlayer`.
enum PcmFormat {
  /// Signed 16-bit integers, little-endian, interleaved.
  ///
  /// This is what most TTS and realtime voice APIs emit (OpenAI, ElevenLabs,
  /// Cartesia, Google, ...).
  s16le(2),

  /// 32-bit IEEE floats, little-endian, interleaved, in the range -1.0 to 1.0.
  f32le(4);

  const PcmFormat(this.bytesPerSample);

  /// Size of a single sample of this format, in bytes.
  final int bytesPerSample;
}
