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

  /// Native accepted-call phase.
  ///
  /// `pendingValidation` means the user accepted natively, but Flutter has not
  /// confirmed the call should open yet. `confirmed` means the package has
  /// cleared the call to continue into the in-app call experience.
  static const String acceptanceState = 'acceptanceState';

  /// Value for [acceptanceState] while backend/app validation is pending.
  static const String acceptanceStatePendingValidation = 'pendingValidation';

  /// Value for [acceptanceState] once the accepted call is confirmed.
  static const String acceptanceStateConfirmed = 'confirmed';

  /// Connected timestamp persisted by the native layer for ongoing-call
  /// restoration after app process death.
  static const String connectedAtMs = 'connectedAtMs';

  /// Machine-readable rejection/end reason surfaced on missed/failure flows.
  static const String outcomeReason = 'outcomeReason';

  /// Value for [launchAction] when the user opened from the ongoing call
  /// notification (Android).
  static const String launchActionOpenOngoing =
      'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING';

  /// Value for [launchAction] when the user opened from the native incoming
  /// call UI without answering yet.
  static const String launchActionOpenIncoming =
      'com.callwave.flutter.methodchannel.ACTION_OPEN_INCOMING';

  /// Value for [launchAction] when the user opened from the missed-call
  /// notification body.
  static const String launchActionOpenMissedCall =
      'com.callwave.flutter.methodchannel.ACTION_OPEN_MISSED_CALL';

  /// Value for [launchAction] when the user chose Call Back from a missed-call
  /// notification.
  static const String launchActionCallback =
      'com.callwave.flutter.methodchannel.ACTION_CALLBACK';
}
