import '../enums/call_event_type.dart';
import '../enums/call_startup_action_type.dart';
import '../enums/call_type.dart';
import '../enums/incoming_accept_strategy.dart';
import '../models/call_data_dto.dart';
import '../models/call_event_dto.dart';
import '../models/call_startup_action_dto.dart';

class PayloadCodec {
  static const String keyCallId = 'callId';
  static const String keyCallerName = 'callerName';
  static const String keyHandle = 'handle';
  static const String keyAvatarUrl = 'avatarUrl';
  static const String keyTimeoutSeconds = 'timeoutSeconds';
  static const String keyCallType = 'callType';
  static const String keyExtra = 'extra';
  static const String keyType = 'type';
  static const String keyTimestampMs = 'timestampMs';
  static const String keyPostCallBehavior = 'postCallBehavior';
  static const String keyIncomingAcceptStrategy = 'incomingAcceptStrategy';
  static const String keyBackgroundDispatcherHandle =
      'backgroundDispatcherHandle';
  static const String keyBackgroundCallbackHandle = 'backgroundCallbackHandle';
  static const String keyStartupActionType = 'startupActionType';

  static Map<String, dynamic> callDataToMap(CallDataDto data) {
    return <String, dynamic>{
      keyCallId: data.callId,
      keyCallerName: data.callerName,
      keyHandle: data.handle,
      keyAvatarUrl: data.avatarUrl,
      keyTimeoutSeconds: data.timeoutSeconds,
      keyCallType: data.callType.wireValue,
      keyExtra: data.extra,
      keyIncomingAcceptStrategy: data.incomingAcceptStrategy.wireValue,
      keyBackgroundDispatcherHandle: data.backgroundDispatcherHandle,
      keyBackgroundCallbackHandle: data.backgroundCallbackHandle,
    };
  }

  static CallDataDto callDataFromMap(Map<String, dynamic> map) {
    return CallDataDto(
      callId: map[keyCallId] as String,
      callerName: map[keyCallerName] as String,
      handle: map[keyHandle] as String,
      avatarUrl: map[keyAvatarUrl] as String?,
      timeoutSeconds: (map[keyTimeoutSeconds] as num?)?.toInt() ?? 30,
      callType: CallType.fromWireValue(
        (map[keyCallType] as String?) ?? CallType.audio.wireValue,
      ),
      extra: _asStringDynamicMap(map[keyExtra]),
      incomingAcceptStrategy: IncomingAcceptStrategy.fromWireValue(
        (map[keyIncomingAcceptStrategy] as String?) ??
            IncomingAcceptStrategy.openImmediately.wireValue,
      ),
      backgroundDispatcherHandle:
          (map[keyBackgroundDispatcherHandle] as num?)?.toInt(),
      backgroundCallbackHandle:
          (map[keyBackgroundCallbackHandle] as num?)?.toInt(),
    );
  }

  static Map<String, dynamic> callEventToMap(CallEventDto event) {
    return <String, dynamic>{
      keyCallId: event.callId,
      keyType: event.type.wireValue,
      keyExtra: event.extra,
      keyTimestampMs: event.timestampMs,
    };
  }

  static CallEventDto? safeCallEventFromMap(Map<String, dynamic> map) {
    final callId = map[keyCallId];
    final rawType = map[keyType];
    final timestamp = map[keyTimestampMs];

    if (callId is! String || rawType is! String || timestamp is! num) {
      return null;
    }

    final type = CallEventType.tryFromWireValue(rawType);
    if (type == null) {
      return null;
    }

    return CallEventDto(
      callId: callId,
      type: type,
      timestampMs: timestamp.toInt(),
      extra: _asStringDynamicMap(map[keyExtra]),
    );
  }

  static Map<String, dynamic> startupActionToMap(CallStartupActionDto action) {
    return <String, dynamic>{
      keyStartupActionType: action.type.wireValue,
      keyCallId: action.callId,
      keyCallerName: action.callerName,
      keyHandle: action.handle,
      keyAvatarUrl: action.avatarUrl,
      keyCallType: action.callType.wireValue,
      keyExtra: action.extra,
    };
  }

  static CallStartupActionDto? safeStartupActionFromMap(
    Map<String, dynamic> map,
  ) {
    final rawType = map[keyStartupActionType];
    final callId = map[keyCallId];
    final callerName = map[keyCallerName];
    final handle = map[keyHandle];
    if (rawType is! String ||
        callId is! String ||
        callerName is! String ||
        handle is! String) {
      return null;
    }

    final type = CallStartupActionType.tryFromWireValue(rawType);
    if (type == null) {
      return null;
    }

    return CallStartupActionDto(
      type: type,
      callId: callId,
      callerName: callerName,
      handle: handle,
      avatarUrl: map[keyAvatarUrl] as String?,
      callType: CallType.fromWireValue(
        (map[keyCallType] as String?) ?? CallType.audio.wireValue,
      ),
      extra: _asStringDynamicMap(map[keyExtra]),
    );
  }

  static Map<String, dynamic>? _asStringDynamicMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    return raw.map<String, dynamic>((key, value) {
      return MapEntry(key.toString(), value);
    });
  }
}
