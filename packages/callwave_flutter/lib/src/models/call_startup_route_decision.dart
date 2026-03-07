import 'call_startup_action.dart';
import '../enums/call_session_state.dart';

/// Startup routing decision for host apps.
///
/// Use this to choose initial app route during cold start.
class CallStartupRouteDecision {
  const CallStartupRouteDecision({
    required this.shouldOpenCall,
    this.callId,
    this.sessionState,
    this.pendingAction,
  });

  const CallStartupRouteDecision.home()
      : shouldOpenCall = false,
        callId = null,
        sessionState = null,
        pendingAction = null;

  const CallStartupRouteDecision.call({
    required String callId,
    required CallSessionState sessionState,
  }) : this(
          shouldOpenCall: true,
          callId: callId,
          sessionState: sessionState,
        );

  /// Use when the user launched from a missed-call notification (tap or Call Back).
  const CallStartupRouteDecision.pendingAction(CallStartupAction action)
      : shouldOpenCall = false,
        callId = null,
        sessionState = null,
        pendingAction = action;

  /// `true` when the app should start directly on the call route.
  final bool shouldOpenCall;

  /// Selected call id for startup call route.
  final String? callId;

  /// State of the selected startup session.
  final CallSessionState? sessionState;

  /// One-shot startup action captured from a missed-call notification launch.
  final CallStartupAction? pendingAction;
}
