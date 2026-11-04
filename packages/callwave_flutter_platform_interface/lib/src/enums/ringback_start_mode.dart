/// Controls when outgoing ringback may start. Incoming calls ignore this setting.
enum RingbackStartMode {
  /// Android waits for screen visibility; iOS retains CallKit audio startup.
  automatic,

  /// Requires screen visibility and explicit host permission on Android/iOS.
  /// iOS additionally waits for CallKit audio activation.
  appControlled;

  String get wireValue => name;

  /// Missing or unknown values preserve automatic startup.
  static RingbackStartMode fromWireValue(String? value) =>
      value == 'appControlled' ? appControlled : automatic;
}
