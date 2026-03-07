import '../engine/callwave_engine.dart';
import '../models/background_incoming_call_validation_request.dart';
import '../models/call_accept_decision.dart';
import '../models/call_decline_decision.dart';
import '../engine/call_session.dart';

typedef CallAcceptValidator = Future<CallAcceptDecision> Function(
  CallSession session,
);
typedef BackgroundIncomingCallValidator = Future<CallAcceptDecision> Function(
  BackgroundIncomingCallValidationRequest request,
);

/// Called in a headless isolate when the user declines from native UI and
/// Flutter is not running. Return [CallDeclineDecision.reported] on success,
/// otherwise [CallDeclineDecision.failed]. On failure, the plugin falls back
/// to missed-call handling.
typedef BackgroundIncomingCallDeclineValidator = Future<CallDeclineDecision>
    Function(
  BackgroundIncomingCallValidationRequest request,
);

/// How to handle native accept events: realtime (immediate) or validated (async check).
sealed class IncomingCallHandling {
  const IncomingCallHandling._();

  const factory IncomingCallHandling.realtime() = RealtimeIncomingCallHandling;

  const factory IncomingCallHandling.validated({
    required CallAcceptValidator validator,
  }) = ValidatedIncomingCallHandling;
}

final class RealtimeIncomingCallHandling extends IncomingCallHandling {
  const RealtimeIncomingCallHandling() : super._();
}

final class ValidatedIncomingCallHandling extends IncomingCallHandling {
  const ValidatedIncomingCallHandling({
    required this.validator,
  }) : super._();

  final CallAcceptValidator validator;
}

/// Configuration for [CallwaveFlutter.configure].
class CallwaveConfiguration {
  const CallwaveConfiguration({
    required this.engine,
    this.incomingCallHandling = const IncomingCallHandling.realtime(),
    this.backgroundIncomingCallValidator,
    this.backgroundIncomingCallDeclineValidator,
  });

  final CallwaveEngine engine;
  final IncomingCallHandling incomingCallHandling;
  final BackgroundIncomingCallValidator? backgroundIncomingCallValidator;

  /// Optional. Runs in headless isolate when user declines from native UI
  /// without opening the app. On failure, falls back to missed-call handling.
  final BackgroundIncomingCallDeclineValidator?
      backgroundIncomingCallDeclineValidator;
}
