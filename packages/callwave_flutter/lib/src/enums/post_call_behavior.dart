/// Configures what happens after the user ends an active call via
/// [CallwaveFlutter.endCall].
///
/// This has no effect when the call ends by timeout, decline, or
/// [CallwaveFlutter.markMissed].
enum PostCallBehavior {
  /// Keep the app in the foreground (default).
  stayOpen,

  /// On Android, move the app task to background after the call ends.
  /// On iOS, this is accepted but has no effect.
  backgroundOnEnded,
}
