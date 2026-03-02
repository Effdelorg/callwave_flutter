enum CallType {
  audio,
  video;

  String get wireValue => name;

  static CallType fromWireValue(String value) {
    return CallType.values.firstWhere(
      (element) => element.wireValue == value,
      orElse: () => CallType.audio,
    );
  }
}
