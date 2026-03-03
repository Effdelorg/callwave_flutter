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
}
