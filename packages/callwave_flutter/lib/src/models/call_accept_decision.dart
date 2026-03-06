/// Result of validating whether an accepted incoming call should proceed.
class CallAcceptDecision {
  const CallAcceptDecision._({
    required this.isAllowed,
    this.reason,
    this.extra,
  });

  const CallAcceptDecision.allow({
    Map<String, dynamic>? extra,
  }) : this._(
          isAllowed: true,
          extra: extra,
        );

  const CallAcceptDecision.reject({
    required CallAcceptRejectReason reason,
    Map<String, dynamic>? extra,
  }) : this._(
          isAllowed: false,
          reason: reason,
          extra: extra,
        );

  final bool isAllowed;
  final CallAcceptRejectReason? reason;
  final Map<String, dynamic>? extra;
}

/// Reason for rejecting an accepted call during validation.
enum CallAcceptRejectReason {
  cancelled,
  ended,
  expired,
  declined,
  unavailable,
  failed,
  unknown,
}
