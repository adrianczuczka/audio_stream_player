/// Playback state of an `AudioStreamPlayer`.
enum PlayerState {
  /// Not playing. The initial state, and the state after [stop] or after the
  /// buffer drains following `endOfStream()`.
  idle,

  /// Consuming buffered audio. A starved player (buffer empty, waiting for
  /// more chunks) is still `playing`; listen to `onUnderrun` to detect
  /// starvation.
  playing,

  /// Paused. Buffered audio is retained and playback resumes where it left
  /// off.
  paused,
}
