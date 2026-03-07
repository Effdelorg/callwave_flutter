/// Result of reporting a declined incoming call while the app is headless.
///
/// Returned by [BackgroundIncomingCallDeclineValidator] when the user declines
/// from native UI and Flutter is not running.
class CallDeclineDecision {
  const CallDeclineDecision._({
    required this.isReported,
    this.reason,
    this.extra,
  });

  const CallDeclineDecision.reported({
    Map<String, dynamic>? extra,
  }) : this._(
          isReported: true,
          extra: extra,
        );

  const CallDeclineDecision.failed({
    required CallDeclineFailureReason reason,
    Map<String, dynamic>? extra,
  }) : this._(
          isReported: false,
          reason: reason,
          extra: extra,
        );

  final bool isReported;
  final CallDeclineFailureReason? reason;
  final Map<String, dynamic>? extra;
}

/// Reason for failing to report a declined call during headless handling.
enum CallDeclineFailureReason {
  /// User cancelled or call was cancelled before report completed.
  cancelled,
  /// Call had already ended.
  ended,
  /// Report window expired (e.g. timeout).
  expired,
  /// Headless isolate or callback unavailable.
  unavailable,
  /// Generic report failure.
  failed,
  /// Unknown or unclassified failure.
  unknown,
}
