import '../engine/callwave_engine.dart';
import '../models/background_incoming_call_validation_request.dart';
import '../models/call_accept_decision.dart';
import '../engine/call_session.dart';

typedef CallAcceptValidator = Future<CallAcceptDecision> Function(
  CallSession session,
);
typedef BackgroundIncomingCallValidator = Future<CallAcceptDecision> Function(
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
  });

  final CallwaveEngine engine;
  final IncomingCallHandling incomingCallHandling;
  final BackgroundIncomingCallValidator? backgroundIncomingCallValidator;
}
