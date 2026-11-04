import '../enums/ringback_start_mode.dart';
import '../enums/call_type.dart';

class CallData {
  static const Object _sentinel = Object();

  const CallData({
    required this.callId,
    required this.callerName,
    required this.handle,
    this.avatarUrl,
    this.timeout = const Duration(seconds: 30),
    this.callType = CallType.audio,
    this.extra,
    this.playRingback = true,
    this.ringbackStartMode = RingbackStartMode.automatic,
    this.maxRingbackDuration = const Duration(seconds: 120),
  });

  final String callId;
  final String callerName;
  final String handle;
  final String? avatarUrl;
  final Duration timeout;
  final CallType callType;
  final Map<String, dynamic>? extra;

  /// Whether the plugin plays a ringback tone for an outgoing call until it
  /// connects or ends. On Android, playback waits for call-screen readiness.
  /// Set to `false` when your media stack plays its own
  /// (for example SIP early media). Ignored for incoming calls.
  final bool playRingback;

  /// Startup policy for outgoing sound; ignored when playRingback is false.
  /// Supported on Android and iOS. Audio routing remains owned by the host.
  final RingbackStartMode ringbackStartMode;

  /// Safety cap for the outgoing ringback tone, in case the call is never
  /// reported connected or ended. Only stops the tone; the call stays active.
  /// Sent in whole seconds, minimum 1 second.
  final Duration maxRingbackDuration;

  CallData copyWith({
    String? callId,
    String? callerName,
    String? handle,
    Object? avatarUrl = _sentinel,
    Duration? timeout,
    CallType? callType,
    Object? extra = _sentinel,
    bool? playRingback,
    RingbackStartMode? ringbackStartMode,
    Duration? maxRingbackDuration,
  }) {
    return CallData(
      callId: callId ?? this.callId,
      callerName: callerName ?? this.callerName,
      handle: handle ?? this.handle,
      avatarUrl: identical(avatarUrl, _sentinel)
          ? this.avatarUrl
          : avatarUrl as String?,
      timeout: timeout ?? this.timeout,
      callType: callType ?? this.callType,
      extra: identical(extra, _sentinel)
          ? this.extra
          : extra as Map<String, dynamic>?,
      playRingback: playRingback ?? this.playRingback,
      ringbackStartMode: ringbackStartMode ?? this.ringbackStartMode,
      maxRingbackDuration: maxRingbackDuration ?? this.maxRingbackDuration,
    );
  }
}
