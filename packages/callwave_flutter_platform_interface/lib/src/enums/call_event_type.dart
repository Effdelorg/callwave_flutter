enum CallEventType {
  /// Android only: emitted when incoming-call notification/full-screen tap
  /// opens the app for custom incoming UI.
  incoming,
  accepted,
  declined,
  ended,
  timeout,
  missed,
  callback,
  started;

  String get wireValue => name;

  static CallEventType? tryFromWireValue(String value) {
    for (final type in CallEventType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}
