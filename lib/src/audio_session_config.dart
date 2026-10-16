/// How an `AudioStreamPlayer` manages the platform audio session (iOS) and
/// audio focus (Android).
///
/// The audio session is shared by every player in the app. On iOS, the
/// configuration of the most recently created player wins. On macOS and web
/// this setting has no effect.
enum AudioSessionConfig {
  /// Speech playback that interrupts other apps' audio while it plays.
  ///
  /// - iOS: the `.playback` category with `.spokenAudio` mode. The session
  ///   is activated on `play()` and deactivated once every player is idle,
  ///   so music from other apps resumes after an utterance. This category
  ///   blocks microphone capture; use [voiceChat] if you record while the
  ///   player plays.
  /// - Android: requests transient audio focus on `play()` and abandons it
  ///   once every player is idle.
  playback,

  /// Speech playback alongside microphone capture, for realtime voice apps.
  ///
  /// - iOS: the `.playAndRecord` category with `.voiceChat` mode and the
  ///   `.defaultToSpeaker` and `.allowBluetooth` options, so a recorder can
  ///   capture the microphone while the player plays and output goes to the
  ///   speaker rather than the receiver. Activation and deactivation work as
  ///   in [playback].
  /// - Android: same as [playback]. Android lets you record while an
  ///   `AudioTrack` plays without extra configuration.
  voiceChat,

  /// The player never touches the audio session or audio focus.
  ///
  /// Use this when you manage the session yourself, for example with the
  /// `audio_session` package. You are then responsible for configuring,
  /// activating and deactivating the iOS session and for handling Android
  /// audio focus.
  manual,
}
