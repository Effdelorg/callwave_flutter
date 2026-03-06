/// Keys that the platform may include in [CallEvent.extra].
///
/// These are set by native implementations (e.g. Android) when emitting events.
/// Apps can read them for routing or UI decisions.
abstract final class CallEventExtraKeys {
  CallEventExtraKeys._();

  /// Indicates how the user opened the app to this event.
  ///
  /// On Android, when the user taps the ongoing call notification (body or
  /// expand), the platform emits an `accepted` or `started` event with this
  /// key set to [launchActionOpenOngoing]. The app can use it to route to the
  /// call screen or re-emit the session for [CallwaveScope] to push
  /// [CallScreen].
  static const String launchAction = 'launchAction';

  /// Value for [launchAction] when the user opened from the ongoing call
  /// notification (Android).
  static const String launchActionOpenOngoing =
      'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING';
}
