/// Recommended keys for [CallData.extra] when integrating with WebRTC/VoIP backends.
///
/// These are conventions, not required. Different SDKs use different names;
/// [CallData.extra] stays flexible for any key-value data.
abstract final class CallDataExtraKeys {
  CallDataExtraKeys._();

  /// Room or meeting identifier (LiveKit, Agora, Twilio Rooms).
  static const String roomId = 'roomId';

  /// Meeting identifier (Zoom, Google Meet, etc.).
  static const String meetingId = 'meetingId';

  /// Remote peer or user identifier (custom signaling, peer-to-peer).
  static const String peerId = 'peerId';

  /// Alternative to [peerId] used by some SDKs.
  static const String remoteUserId = 'remoteUserId';

  /// WebSocket signaling server URL.
  static const String signalingUrl = 'signalingUrl';

  /// JWT or access token (LiveKit, Agora, etc.).
  static const String token = 'token';

  /// SIP URI for SIP-based SDKs.
  static const String sipUri = 'sipUri';

  /// Preferred local/self participant display name for fallback tiles.
  static const String localDisplayName = 'localDisplayName';
}
