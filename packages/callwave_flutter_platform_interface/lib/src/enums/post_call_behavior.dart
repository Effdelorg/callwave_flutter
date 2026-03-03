/// Platform-level post-call behavior enum with wire serialization.
enum PostCallBehavior {
  stayOpen,
  backgroundOnEnded;

  /// Wire value for method channel serialization.
  String get wireValue => name;

  /// Parses a wire value. Returns [stayOpen] for null/unknown values.
  static PostCallBehavior fromWireValue(String? value) {
    if (value == null) {
      return PostCallBehavior.stayOpen;
    }
    return PostCallBehavior.values.firstWhere(
      (element) => element.wireValue == value,
      orElse: () => PostCallBehavior.stayOpen,
    );
  }
}
