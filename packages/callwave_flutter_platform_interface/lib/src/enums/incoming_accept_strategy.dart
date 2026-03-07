enum IncomingAcceptStrategy {
  openImmediately('openImmediately'),
  deferOpenUntilConfirmed('deferOpenUntilConfirmed');

  const IncomingAcceptStrategy(this.wireValue);

  final String wireValue;

  /// Parses [raw]. Returns [openImmediately] for unknown or empty values.
  static IncomingAcceptStrategy fromWireValue(String raw) {
    for (final value in IncomingAcceptStrategy.values) {
      if (value.wireValue == raw) {
        return value;
      }
    }
    return IncomingAcceptStrategy.openImmediately;
  }
}
