import 'dart:async';

import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart';
import 'package:flutter/services.dart';

import 'channel_names.dart';

class MethodChannelCallwaveFlutter extends CallwaveFlutterPlatform {
  MethodChannelCallwaveFlutter();

  static void registerWith() {
    CallwaveFlutterPlatform.instance = MethodChannelCallwaveFlutter();
  }

  final MethodChannel _methodChannel = const MethodChannel(ChannelNames.method);
  final EventChannel _eventChannel = const EventChannel(ChannelNames.events);

  bool _isInitialized = false;
  Stream<CallEventDto>? _events;

  @override
  Stream<CallEventDto> get events {
    _events ??= _eventChannel
        .receiveBroadcastStream()
        .map<CallEventDto?>(_safeDecodeEvent)
        .where((event) => event != null)
        .cast<CallEventDto>();
    return _events!;
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _methodChannel.invokeMethod<void>('initialize');
    _isInitialized = true;
  }

  @override
  Future<void> showIncomingCall(CallDataDto data) async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'showIncomingCall',
      PayloadCodec.callDataToMap(data),
    );
  }

  @override
  Future<void> showOutgoingCall(CallDataDto data) async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'showOutgoingCall',
      PayloadCodec.callDataToMap(data),
    );
  }

  @override
  Future<void> registerBackgroundIncomingCallValidator({
    required int backgroundDispatcherHandle,
    required int backgroundCallbackHandle,
  }) async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'registerBackgroundIncomingCallValidator',
      <String, dynamic>{
        PayloadCodec.keyBackgroundDispatcherHandle: backgroundDispatcherHandle,
        PayloadCodec.keyBackgroundCallbackHandle: backgroundCallbackHandle,
      },
    );
  }

  @override
  Future<void> clearBackgroundIncomingCallValidator() async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'clearBackgroundIncomingCallValidator',
    );
  }

  @override
  Future<void> endCall(String callId) async {
    await initialize();
    await _methodChannel.invokeMethod<void>('endCall', <String, dynamic>{
      PayloadCodec.keyCallId: callId,
    });
  }

  @override
  Future<void> acceptCall(String callId) async {
    await initialize();
    await _methodChannel.invokeMethod<void>('acceptCall', <String, dynamic>{
      PayloadCodec.keyCallId: callId,
    });
  }

  @override
  Future<void> confirmAcceptedCall(String callId) async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'confirmAcceptedCall',
      <String, dynamic>{
        PayloadCodec.keyCallId: callId,
      },
    );
  }

  @override
  Future<void> declineCall(String callId) async {
    await initialize();
    await _methodChannel.invokeMethod<void>('declineCall', <String, dynamic>{
      PayloadCodec.keyCallId: callId,
    });
  }

  @override
  Future<void> markMissed(String callId, {Map<String, dynamic>? extra}) async {
    await initialize();
    await _methodChannel.invokeMethod<void>('markMissed', <String, dynamic>{
      PayloadCodec.keyCallId: callId,
      if (extra != null) PayloadCodec.keyExtra: extra,
    });
  }

  @override
  Future<List<String>> getActiveCallIds() async {
    await initialize();
    final raw = await _methodChannel.invokeMethod<List<dynamic>>(
      'getActiveCallIds',
    );
    if (raw == null) {
      return const <String>[];
    }
    return raw.whereType<String>().toList(growable: false);
  }

  @override
  Future<List<CallEventDto>> getActiveCallEventSnapshots() async {
    await initialize();
    final raw = await _methodChannel.invokeMethod<List<dynamic>>(
      'getActiveCallEventSnapshots',
    );
    if (raw == null) {
      return const <CallEventDto>[];
    }

    final snapshots = <CallEventDto>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final normalized =
          item.map<String, dynamic>((dynamic key, dynamic value) {
        return MapEntry(key.toString(), value);
      });
      final dto = PayloadCodec.safeCallEventFromMap(normalized);
      if (dto != null) {
        snapshots.add(dto);
      }
    }
    return snapshots;
  }

  @override
  Future<void> syncActiveCallsToEvents() async {
    await initialize();
    await _methodChannel.invokeMethod<void>('syncActiveCallsToEvents');
  }

  @override
  Future<bool> requestNotificationPermission() async {
    await initialize();
    final granted = await _methodChannel.invokeMethod<bool>(
      'requestNotificationPermission',
    );
    return granted ?? false;
  }

  @override
  Future<void> requestFullScreenIntentPermission() async {
    await initialize();
    await _methodChannel
        .invokeMethod<void>('requestFullScreenIntentPermission');
  }

  @override
  Future<void> setPostCallBehavior(PostCallBehavior behavior) async {
    await initialize();
    await _methodChannel.invokeMethod<void>(
      'setPostCallBehavior',
      <String, dynamic>{
        PayloadCodec.keyPostCallBehavior: behavior.wireValue,
      },
    );
  }

  CallEventDto? _safeDecodeEvent(dynamic raw) {
    try {
      if (raw is! Map) {
        return null;
      }
      final normalized = raw.map<String, dynamic>((dynamic key, dynamic value) {
        return MapEntry(key.toString(), value);
      });
      return PayloadCodec.safeCallEventFromMap(normalized);
    } catch (_) {
      return null;
    }
  }
}
