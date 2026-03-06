import 'dart:async';
import 'dart:math' as math;

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_platform_interface/callwave_flutter_platform_interface.dart'
    as platform;
import 'package:callwave_flutter_example/example_camera_controller.dart';
import 'package:callwave_flutter_example/example_video_call_screen.dart';
import 'package:callwave_flutter_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform fakePlatform;
  late _FakeCameraHandle fakeCamera;

  setUp(() {
    fakePlatform = _FakePlatform();
    fakeCamera = _FakeCameraHandle();
    platform.CallwaveFlutterPlatform.instance = fakePlatform;
    CallwaveFlutter.instance.setEngine(_TestEngine());
  });

  tearDown(() async {
    CallwaveFlutter.instance.setEngine(_TestEngine());
    await fakePlatform.dispose();
  });

  testWidgets('app boots to home screen', (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    expect(find.text('Callwave Example'), findsOneWidget);
    expect(find.text('Call ID'), findsOneWidget);
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('demo renders explicit incoming/outgoing audio-video buttons',
      (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    expect(find.text('Incoming Audio'), findsOneWidget);
    expect(find.text('Incoming Video'), findsOneWidget);
    expect(find.text('Outgoing Audio'), findsOneWidget);
    expect(find.text('Outgoing Video'), findsOneWidget);
    expect(find.text('Conference Audio'), findsOneWidget);
    expect(find.text('Conference Video'), findsOneWidget);
    expect(find.text('Cycle Speaker'), findsOneWidget);

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference audio preview opens conference call UI',
      (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Conference Audio'));
    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('conference-view')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('conference-controls-row')),
        findsOneWidget);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('Cam'), findsNothing);
    expect(find.text('End'), findsOneWidget);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference video preview opens conference call UI',
      (tester) async {
    await tester.pumpWidget(CallwaveExampleApp(cameraController: fakeCamera));
    await tester.pump();

    await tester.tap(find.text('Conference Video'));
    await _pumpUntilCallScreen(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('conference-view')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('conference-controls-row')),
        findsOneWidget);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('Cam'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference video renders preview only for local tile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(CallwaveExampleApp(cameraController: fakeCamera));
    await tester.pump();

    await tester.tap(find.text('Conference Video'));
    await _pumpUntilCallScreen(tester);
    expect(find.byType(ExampleVideoCallScreen), findsOneWidget);
    final renderedScreen = tester
        .widget<ExampleVideoCallScreen>(find.byType(ExampleVideoCallScreen));
    expect(identical(renderedScreen.cameraController, fakeCamera), isTrue);

    await tester.tap(find.byIcon(Icons.videocam_off).first);
    await tester.pump();
    if (fakeCamera.lastEnabled != true) {
      await tester.tap(find.byIcon(Icons.videocam_off).first);
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(fakeCamera.lastEnabled, isTrue);
    expect(fakeCamera.state, ExampleCameraState.ready);
    expect(fakeCamera.isPreviewReady, isTrue);

    expect(
      find.byKey(const ValueKey<String>('video-preview-conference-speaker-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('video-preview-conference-speaker-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('video-preview-conference-speaker-3')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('video-preview-conference-local-you')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('video-preview-fit-conference-local-you'),
      ),
      findsOneWidget,
    );
    final conferenceFitFinder = find.byKey(
      const ValueKey<String>('video-preview-fit-conference-local-you'),
    );
    final conferencePreviewFinder = find.byKey(
      const ValueKey<String>('video-preview-conference-local-you'),
    );
    final fitSize = tester.getSize(conferenceFitFinder);
    final previewSize = tester.getSize(conferencePreviewFinder);
    expect(previewSize.width, lessThanOrEqualTo(fitSize.width));
    expect(previewSize.height, lessThanOrEqualTo(fitSize.height));
    expect(
      previewSize.width / previewSize.height,
      closeTo(16 / 9, 0.01),
    );
    final isWidthBound = (fitSize.width - previewSize.width).abs() < 0.5;
    final isHeightBound = (fitSize.height - previewSize.height).abs() < 0.5;
    expect(isWidthBound || isHeightBound, isTrue);
    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Milo'), findsOneWidget);
    expect(find.text('Nora'), findsOneWidget);
    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('conference video shows inline retry card when permission denied',
      (tester) async {
    fakeCamera.denyOnEnable = true;
    await tester.pumpWidget(CallwaveExampleApp(cameraController: fakeCamera));
    await tester.pump();

    await tester.tap(find.text('Conference Video'));
    await _pumpUntilCallScreen(tester);
    expect(find.byType(ExampleVideoCallScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.videocam_off).first);
    await tester.pump();
    if (fakeCamera.lastEnabled != true) {
      await tester.tap(find.byIcon(Icons.videocam_off).first);
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(
      find.text('Camera permission is needed for video preview.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));
    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('one-to-one connected video defaults to split layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = CallSession(
      callData: const CallData(
        callId: 'one-to-one-video',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.video,
      ),
      isOutgoing: false,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExampleVideoCallScreen(
          session: session,
          cameraController: fakeCamera,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await session.toggleCamera();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    final splitRemoteSurface = find.byKey(
      const ValueKey<String>('one-to-one-video-split-remote-surface'),
    );
    final splitLocalSurface = find.byKey(
      const ValueKey<String>('one-to-one-video-split-local-surface'),
    );
    expect(splitRemoteSurface, findsOneWidget);
    expect(splitLocalSurface, findsOneWidget);
    _expectSquareSurface(tester, splitRemoteSurface);
    _expectSquareSurface(tester, splitLocalSurface);
    expect(
      find.byKey(const ValueKey<String>('video-preview-fit-one-to-one')),
      findsOneWidget,
    );
    final fitFinder =
        find.byKey(const ValueKey<String>('video-preview-fit-one-to-one'));
    final previewFinder =
        find.byKey(const ValueKey<String>('video-preview-one-to-one'));
    final fitSize = tester.getSize(fitFinder);
    final previewSize = tester.getSize(previewFinder);
    expect(previewSize.width, greaterThanOrEqualTo(fitSize.width));
    expect(previewSize.height, greaterThanOrEqualTo(fitSize.height));
    expect(previewSize.width / previewSize.height, closeTo(16 / 9, 0.01));
    final widthBound = (previewSize.width - fitSize.width).abs() < 0.5;
    final heightBound = (previewSize.height - fitSize.height).abs() < 0.5;
    expect(widthBound || heightBound, isTrue);
    expect(find.text('Mic'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('Cam'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    session.reportEnded();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('one-to-one connected video supports split to pip to split',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = CallSession(
      callData: const CallData(
        callId: 'one-to-one-video-pip',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.video,
      ),
      isOutgoing: false,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExampleVideoCallScreen(
          session: session,
          cameraController: fakeCamera,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await session.toggleCamera();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    final splitRemoteRect = tester.getRect(
      find.byKey(
          const ValueKey<String>('one-to-one-video-split-remote-surface')),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-remote-tap')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-pip-surface')),
      findsOneWidget,
    );
    _expectSquareSurface(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
    );
    _expectSquareSurface(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-pip-surface')),
    );
    final primaryRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
    );
    final pipRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-pip-surface')),
    );
    final clusterRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-pip-cluster')),
    );
    final controlsRect = tester.getRect(
      find.byKey(const ValueKey<String>('conference-controls-row')),
    );
    final screenRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-pip-view')),
    );
    expect(primaryRect.width, greaterThan(splitRemoteRect.width));
    _expectDetachedPipLayout(
      primaryRect: primaryRect,
      pipRect: pipRect,
      clusterRect: clusterRect,
      screenRect: screenRect,
      controlsRect: controlsRect,
    );
    _expectPrimaryNearMaxForPip(
      primaryRect: primaryRect,
      screenRect: screenRect,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-tap-target')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    session.reportEnded();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('one-to-one permission card remains visible in split and pip',
      (tester) async {
    fakeCamera.denyOnEnable = true;
    final session = CallSession(
      callData: const CallData(
        callId: 'one-to-one-video-permission',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.video,
      ),
      isOutgoing: false,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExampleVideoCallScreen(
          session: session,
          cameraController: fakeCamera,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await session.toggleCamera();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(
      find.text('Camera permission is needed for video preview.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-remote-tap')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Camera permission is needed for video preview.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
      findsOneWidget,
    );
    session.reportEnded();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('example local display name extra handles non-string safely',
      (tester) async {
    final session = CallSession(
      callData: const CallData(
        callId: 'one-to-one-video-extra-safety',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.video,
        extra: <String, Object?>{
          CallDataExtraKeys.localDisplayName: 123,
        },
      ),
      isOutgoing: false,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ExampleVideoCallScreen(
          session: session,
          cameraController: fakeCamera,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    session.reportEnded();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('video session detaches camera handle after call ends',
      (tester) async {
    await tester.pumpWidget(CallwaveExampleApp(cameraController: fakeCamera));
    await tester.pump();

    await tester.tap(find.text('Conference Video'));
    await _pumpUntilCallScreen(tester);
    expect(find.byType(ExampleVideoCallScreen), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(fakeCamera.attachCount, greaterThanOrEqualTo(1));
    expect(fakeCamera.activeCallIds, isNotEmpty);

    for (final session in CallwaveFlutter.instance.activeSessions) {
      session.reportEnded();
    }
    await tester.pump(const Duration(seconds: 4));

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
    expect(fakeCamera.detachCount, greaterThanOrEqualTo(1));
    expect(fakeCamera.activeCallIds, isEmpty);
  });

  testWidgets('demo sends selected call types to platform', (tester) async {
    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Incoming Video'));
    await tester.pump();
    expect(fakePlatform.lastIncomingCallData, isNotNull);
    expect(
        fakePlatform.lastIncomingCallData!.callType, platform.CallType.video);
    expect(fakePlatform.lastIncomingCallData!.callId, _FakePlatform.callId);

    await tester.tap(find.text('Outgoing Audio'));
    await tester.pump();
    expect(fakePlatform.lastOutgoingCallData, isNotNull);
    expect(
        fakePlatform.lastOutgoingCallData!.callType, platform.CallType.audio);
    expect(fakePlatform.lastOutgoingCallData!.callId, _FakePlatform.callId);

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('in-flight guard prevents duplicate call launch taps',
      (tester) async {
    fakePlatform.pendingIncomingCallCompleter = Completer<void>();

    await tester.pumpWidget(const CallwaveExampleApp());
    await tester.pump();

    await tester.tap(find.text('Incoming Video'));
    await tester.tap(find.text('Incoming Video'));
    await tester.pump();

    expect(fakePlatform.incomingCallCount, 1);

    fakePlatform.pendingIncomingCallCompleter?.complete();
    await tester.pump();
    await tester.pump();

    await _disposeRenderedApp(tester, wait: const Duration(milliseconds: 50));
  });

  testWidgets('accepted event opens session-driven call screen',
      (tester) async {
    fakePlatform.initialEventTypes = <platform.CallEventType>[
      platform.CallEventType.accepted,
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpUntilCallScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('accepted launchAction event opens session-driven call screen',
      (tester) async {
    fakePlatform.initialEvents = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'launchAction':
              'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING',
        },
      ),
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpUntilCallScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('started launchAction event opens session-driven call screen',
      (tester) async {
    fakePlatform.initialEvents = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: const <String, dynamic>{
          'launchAction':
              'com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING',
        },
      ),
    ];

    await tester.pumpWidget(const CallwaveExampleApp());
    await _pumpUntilCallScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('ended event transitions startup-routed session to ended state',
      (tester) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final startupDecision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();
    await tester.pumpWidget(
      CallwaveExampleApp(startupDecision: startupDecision),
    );
    await _pumpUntilCallScreen(tester);
    expect(find.byType(CallScreen), findsOneWidget);

    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final session = CallwaveFlutter.instance.getSession(_FakePlatform.callId);
    expect(session, isNotNull);
    expect(session!.state, CallSessionState.ended);
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('startup decision routes accepted cold start directly to call',
      (tester) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.accepted,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final startupDecision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();
    await tester.pumpWidget(
      CallwaveExampleApp(startupDecision: startupDecision),
    );
    await _pumpUntilCallScreen(tester);

    expect(startupDecision.shouldOpenCall, isTrue);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Call ID'), findsNothing);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });

  testWidgets('startup decision routes started cold start directly to call',
      (tester) async {
    fakePlatform.activeCallIds = <String>[_FakePlatform.callId];
    fakePlatform.activeCallSnapshots = <platform.CallEventDto>[
      platform.CallEventDto(
        callId: _FakePlatform.callId,
        type: platform.CallEventType.started,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    final startupDecision =
        await CallwaveFlutter.instance.prepareStartupRouteDecision();
    await tester.pumpWidget(
      CallwaveExampleApp(startupDecision: startupDecision),
    );
    await _pumpUntilCallScreen(tester);

    expect(startupDecision.shouldOpenCall, isTrue);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('Call ID'), findsNothing);
    fakePlatform.emit(type: platform.CallEventType.ended);
    await tester.pump();
    await _disposeRenderedApp(tester, wait: const Duration(seconds: 4));
  });
}

Future<void> _pumpUntilCallScreen(WidgetTester tester) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CallScreen).evaluate().isNotEmpty ||
        find.byType(ExampleVideoCallScreen).evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _disposeRenderedApp(
  WidgetTester tester, {
  required Duration wait,
}) async {
  await tester.pump(wait);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _FakePlatform extends platform.CallwaveFlutterPlatform {
  static const String callId = 'demo-call-001';

  _FakePlatform();

  late final StreamController<platform.CallEventDto> _controller =
      StreamController<platform.CallEventDto>.broadcast(
    onListen: _emitInitialEvents,
  );
  List<platform.CallEventType> _initialEventTypes = <platform.CallEventType>[];
  List<platform.CallEventDto> _initialEvents = <platform.CallEventDto>[];
  List<String> activeCallIds = const <String>[];
  List<platform.CallEventDto> activeCallSnapshots =
      const <platform.CallEventDto>[];
  platform.CallDataDto? lastIncomingCallData;
  platform.CallDataDto? lastOutgoingCallData;
  int incomingCallCount = 0;
  int outgoingCallCount = 0;
  Completer<void>? pendingIncomingCallCompleter;
  Completer<void>? pendingOutgoingCallCompleter;
  bool _didEmitInitialEvents = false;

  set initialEventTypes(List<platform.CallEventType> value) {
    _initialEventTypes = List<platform.CallEventType>.of(value);
    _initialEvents = <platform.CallEventDto>[];
    _didEmitInitialEvents = false;
    if (_controller.hasListener) {
      _emitInitialEvents();
    }
  }

  set initialEvents(List<platform.CallEventDto> value) {
    _initialEvents = List<platform.CallEventDto>.of(value);
    _initialEventTypes = <platform.CallEventType>[];
    _didEmitInitialEvents = false;
    if (_controller.hasListener) {
      _emitInitialEvents();
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Stream<platform.CallEventDto> get events => _controller.stream;

  void _emitInitialEvents() {
    if (_didEmitInitialEvents) {
      return;
    }
    _didEmitInitialEvents = true;
    if (_initialEvents.isNotEmpty) {
      for (final event in _initialEvents) {
        _controller.add(event);
      }
      return;
    }
    for (final type in _initialEventTypes) {
      emit(type: type);
    }
  }

  void emit({
    required platform.CallEventType type,
    Map<String, dynamic>? extra,
  }) {
    _controller.add(
      platform.CallEventDto(
        callId: callId,
        type: type,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        extra: extra,
      ),
    );
  }

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<List<String>> getActiveCallIds() async =>
      List<String>.of(activeCallIds);

  @override
  Future<List<platform.CallEventDto>> getActiveCallEventSnapshots() async {
    return List<platform.CallEventDto>.of(activeCallSnapshots);
  }

  @override
  Future<void> syncActiveCallsToEvents() async {
    for (final event in activeCallSnapshots) {
      _controller.add(event);
    }
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> markMissed(String callId) async {}

  @override
  Future<void> requestFullScreenIntentPermission() async {}

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> setPostCallBehavior(platform.PostCallBehavior behavior) async {}

  @override
  Future<void> showIncomingCall(platform.CallDataDto data) async {
    lastIncomingCallData = data;
    incomingCallCount += 1;
    final completer = pendingIncomingCallCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> showOutgoingCall(platform.CallDataDto data) async {
    lastOutgoingCallData = data;
    outgoingCallCount += 1;
    final completer = pendingOutgoingCallCompleter;
    if (completer != null) {
      await completer.future;
    }
  }
}

class _TestEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {
    session.reportConnected();
  }

  @override
  Future<void> onStartCall(CallSession session) async {
    session.reportConnected();
  }

  @override
  Future<void> onEndCall(CallSession session) async {}

  @override
  Future<void> onDeclineCall(CallSession session) async {}

  @override
  Future<void> onMuteChanged(CallSession session, bool muted) async {}

  @override
  Future<void> onSpeakerChanged(CallSession session, bool speakerOn) async {}

  @override
  Future<void> onCameraChanged(CallSession session, bool enabled) async {}

  @override
  Future<void> onCameraSwitch(CallSession session) async {}

  @override
  Future<void> onDispose(CallSession session) async {}
}

class _FakeCameraHandle extends ExampleCameraHandle {
  final Set<String> activeCallIds = <String>{};
  bool denyOnEnable = false;
  int attachCount = 0;
  int detachCount = 0;
  bool? lastEnabled;

  ExampleCameraState _state = ExampleCameraState.idle;
  String? _errorMessage;
  bool _isPreviewReady = false;

  @override
  ExampleCameraState get state => _state;

  @override
  bool get isPreviewReady => _isPreviewReady;

  @override
  double? get previewAspectRatio => 16 / 9;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> attachSession(String callId) async {
    attachCount += 1;
    activeCallIds.add(callId);
  }

  @override
  Future<void> detachSession(String callId) async {
    if (activeCallIds.remove(callId)) {
      detachCount += 1;
    }
  }

  @override
  Widget buildPreview({Key? key}) {
    return ColoredBox(
      key: key,
      color: const Color(0xFF1565C0),
    );
  }

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> retryPermission(String callId) async {
    await setCameraEnabled(callId, true);
  }

  @override
  Future<void> setCameraEnabled(String callId, bool enabled) async {
    activeCallIds.add(callId);
    lastEnabled = enabled;
    if (!enabled) {
      _state = ExampleCameraState.idle;
      _errorMessage = null;
      _isPreviewReady = false;
      notifyListeners();
      return;
    }
    if (denyOnEnable) {
      _state = ExampleCameraState.errorPermissionDenied;
      _errorMessage = 'Camera permission is needed for video preview.';
      _isPreviewReady = false;
      notifyListeners();
      return;
    }
    _state = ExampleCameraState.ready;
    _errorMessage = null;
    _isPreviewReady = true;
    notifyListeners();
  }
}

void _expectSquareSurface(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  expect((size.width - size.height).abs(), lessThan(0.5));
}

void _expectPrimaryNearMaxForPip({
  required Rect primaryRect,
  required Rect screenRect,
}) {
  final stageWidth = math.max(
    0.0,
    screenRect.width - (CallScreenTheme.oneToOnePipStageHorizontalPadding * 2),
  );
  final stageHeight = math.max(
    0.0,
    screenRect.height -
        (CallScreenTheme.oneToOnePipStageTopPadding +
            CallScreenTheme.oneToOnePipStageBottomPadding),
  );
  final expected = CallScreenTheme.oneToOnePrimarySquareSizeForDetachedPip(
    stageWidth: stageWidth,
    stageHeight: stageHeight,
    primaryLeadingInset: CallScreenTheme.oneToOnePipPrimaryLeadingInset,
    detachedGap: CallScreenTheme.oneToOnePipDetachedGap,
  );
  expect(primaryRect.width, closeTo(expected, 0.5));
}

void _expectDetachedPipLayout({
  required Rect primaryRect,
  required Rect pipRect,
  required Rect clusterRect,
  required Rect screenRect,
  required Rect controlsRect,
}) {
  const tolerance = 0.5;
  expect(
    primaryRect.left - clusterRect.left,
    closeTo(CallScreenTheme.oneToOnePipPrimaryLeadingInset, tolerance),
  );
  expect(
    pipRect.right,
    closeTo(primaryRect.right, tolerance),
  );
  expect(
    pipRect.top,
    greaterThanOrEqualTo(
      primaryRect.bottom + CallScreenTheme.oneToOnePipDetachedGap - tolerance,
    ),
  );
  expect(pipRect.right, lessThanOrEqualTo(screenRect.right + tolerance));
  expect(pipRect.bottom, lessThanOrEqualTo(screenRect.bottom + tolerance));
  expect(pipRect.bottom, lessThanOrEqualTo(controlsRect.top + tolerance));
}
