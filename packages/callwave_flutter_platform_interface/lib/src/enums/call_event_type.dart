enum CallEventType {
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
