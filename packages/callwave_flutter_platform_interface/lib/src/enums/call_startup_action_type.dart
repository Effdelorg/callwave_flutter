enum CallStartupActionType {
  openMissedCall,
  callback;

  String get wireValue => name;

  static CallStartupActionType? tryFromWireValue(String value) {
    for (final type in CallStartupActionType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}
