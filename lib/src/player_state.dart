/// Playback state of an `AudioStreamPlayer`.
enum PlayerState {
  /// Not playing. The initial state, and the state after `stop()` or after the
  /// buffer drains following `endOfStream()`.
  idle,

  /// Consuming buffered audio. A starved player (buffer empty, waiting for
  /// more chunks) is still `playing`; listen to `onUnderrun` to detect
  /// starvation.
  playing,

  /// Paused. Buffered audio is retained and playback resumes where it left
  /// off.
  ///
  /// Besides `pause()`, the system can pause a player: an iOS audio session
  /// interruption (a phone call or Siri) or an Android audio focus loss
  /// moves a playing player to `paused`. If the interruption is transient
  /// and the system signals that playback may continue, the player resumes
  /// by itself. Otherwise it stays paused until you call `play()`.
  paused,
}
