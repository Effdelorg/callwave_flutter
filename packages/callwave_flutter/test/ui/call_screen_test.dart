import 'dart:math' as math;

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter/src/ui/widgets/call_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('auto returns on ended when previous route exists',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final session = _buildSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    _pushCallScreen(navigatorKey, session);
    await tester.pump(const Duration(milliseconds: 350));
    expect(navigatorKey.currentState!.canPop(), isTrue);

    session.reportEnded();
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(navigatorKey.currentState!.canPop(), isFalse);
  });

  testWidgets('does not pop when call screen is root route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final session = _buildSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: CallScreen(session: session),
      ),
    );

    expect(navigatorKey.currentState!.canPop(), isFalse);

    session.reportEnded();
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onCallEnded callback runs exactly once when provided', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final session = _buildSession();
    addTearDown(session.dispose);
    var callbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          session: session,
          onCallEnded: () {
            callbackCount += 1;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    session.reportEnded();
    session.reportEnded();
    await tester.pump();
    await _pumpThroughAutoDismiss(tester);

    expect(callbackCount, 1);
  });

  test('session mode maps state and delegates actions', () async {
    var acceptCalls = 0;
    var endCalls = 0;
    final session = _buildSession(
      acceptNative: (_) async {
        acceptCalls += 1;
      },
      endNative: (_) async {
        endCalls += 1;
      },
    );
    addTearDown(session.dispose);

    final controller = CallScreenController(session: session);
    addTearDown(controller.dispose);

    expect(controller.status, CallStatus.ringing);

    controller.acceptCall();
    await Future<void>.delayed(Duration.zero);
    expect(acceptCalls, 1);

    session.reportConnected();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, CallStatus.connected);

    controller.endCall();
    await Future<void>.delayed(Duration.zero);
    expect(endCalls, 1);
  });

  testWidgets('ringing actions use equal sizes and red/green colors', (
    tester,
  ) async {
    final session = _buildSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    final declineButton = find.byWidgetPredicate(
      (widget) => widget is CallActionButton && widget.label == 'Decline',
    );
    final acceptButton = find.byWidgetPredicate(
      (widget) => widget is CallActionButton && widget.label == 'Accept',
    );

    expect(declineButton, findsOneWidget);
    expect(acceptButton, findsOneWidget);

    final declineContainer = find.descendant(
      of: declineButton,
      matching: find.byType(AnimatedContainer),
    );
    final acceptContainer = find.descendant(
      of: acceptButton,
      matching: find.byType(AnimatedContainer),
    );

    final declineSize = tester.getSize(declineContainer);
    final acceptSize = tester.getSize(acceptContainer);

    expect(declineSize.width, CallScreenTheme.actionButtonSize);
    expect(declineSize.height, CallScreenTheme.actionButtonSize);
    expect(acceptSize.width, CallScreenTheme.actionButtonSize);
    expect(acceptSize.height, CallScreenTheme.actionButtonSize);
    expect(declineSize, acceptSize);

    final declineWidget = tester.widget<AnimatedContainer>(declineContainer);
    final acceptWidget = tester.widget<AnimatedContainer>(acceptContainer);

    final declineDecoration = declineWidget.decoration! as BoxDecoration;
    final acceptDecoration = acceptWidget.decoration! as BoxDecoration;

    expect(declineDecoration.color, CallScreenTheme.endCallColor);
    expect(acceptDecoration.color, CallScreenTheme.acceptCallColor);
  });

  testWidgets('one-to-one video mode renders built-in video surface', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-view')),
      findsOneWidget,
    );
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
    _expectSquare(tester, splitRemoteSurface);
    _expectSquare(tester, splitLocalSurface);
    expect(
      find.byKey(const ValueKey<String>('conference-controls-row')),
      findsOneWidget,
    );
    expect(_actionButtonFinder('Mic'), findsOneWidget);
    expect(_actionButtonFinder('Speaker'), findsOneWidget);
    expect(_actionButtonFinder('Cam'), findsOneWidget);
    expect(_actionButtonFinder('Camera On'), findsNothing);
    final splitRemoteRect = tester.getRect(splitRemoteSurface);

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-local-tap')),
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
      find.byKey(const ValueKey<String>('one-to-one-video-view')),
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
    _expectSquare(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
    );
    _expectSquare(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-pip-surface')),
    );
    session.dispose();
  });

  testWidgets('custom one-to-one builders support split to pip swapping', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          session: session,
          oneToOneRemoteVideoBuilder: (_, __) => const ColoredBox(
            color: Colors.green,
            child: Center(child: Text('REMOTE')),
          ),
          oneToOneLocalVideoBuilder: (_, __) => const ColoredBox(
            color: Colors.blue,
            child: Center(child: Text('LOCAL')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    expect(find.text('REMOTE'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    _expectSquare(
      tester,
      find.byKey(
          const ValueKey<String>('one-to-one-video-split-remote-surface')),
    );
    _expectSquare(
      tester,
      find.byKey(
          const ValueKey<String>('one-to-one-video-split-local-surface')),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-local-tap')),
    );
    await tester.pumpAndSettle();

    final primarySurface = find.byKey(
      const ValueKey<String>('one-to-one-video-primary-surface'),
    );
    final pipSurface = find.byKey(
      const ValueKey<String>('one-to-one-video-pip-surface'),
    );
    expect(primarySurface, findsOneWidget);
    expect(pipSurface, findsOneWidget);
    expect(
      find.descendant(of: primarySurface, matching: find.text('LOCAL')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pipSurface, matching: find.text('REMOTE')),
      findsOneWidget,
    );
    _expectSquare(tester, primarySurface);
    _expectSquare(tester, pipSurface);
    final primaryRect = tester.getRect(primarySurface);
    final pipRect = tester.getRect(pipSurface);
    final clusterRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-pip-cluster')),
    );
    final controlsRect = tester.getRect(
      find.byKey(const ValueKey<String>('conference-controls-row')),
    );
    final screenRect = tester.getRect(
      find.byKey(const ValueKey<String>('one-to-one-video-view')),
    );
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
      find.byKey(const ValueKey<String>('one-to-one-video-pip-tap-target')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: primarySurface, matching: find.text('REMOTE')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-tap-target')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    session.dispose();
  });

  testWidgets('connected one-to-one fallback rendering stays safe', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connected,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    _expectSquare(
      tester,
      find.byKey(
          const ValueKey<String>('one-to-one-video-split-remote-surface')),
    );
    _expectSquare(
      tester,
      find.byKey(
          const ValueKey<String>('one-to-one-video-split-local-surface')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-remote-tap')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
      findsOneWidget,
    );
    _expectSquare(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
    );
    _expectSquare(
      tester,
      find.byKey(const ValueKey<String>('one-to-one-video-pip-surface')),
    );
    expect(tester.takeException(), isNull);
    session.dispose();
  });

  testWidgets('pre-connected video actions keep camera beside speaker', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connecting,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    expect(find.text('Connecting...'), findsOneWidget);
    _expectActionOrder(
      tester: tester,
      labels: const ['Speaker', 'Camera On', 'End'],
    );
  });

  testWidgets('ended video actions keep end button on the right', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connecting,
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    session.reportEnded();
    await tester.pump();

    expect(find.text('Call Ended'), findsOneWidget);
    _expectActionOrder(
      tester: tester,
      labels: const ['Speaker', 'Camera On', 'End'],
    );
    await _pumpThroughAutoDismiss(tester);
  });

  testWidgets('failed restored call shows unable to rejoin message', (
    tester,
  ) async {
    final session = CallSession(
      callData: const CallData(
        callId: 'test-call-id',
        callerName: 'Ava',
        handle: '+1 555 0101',
      ),
      isOutgoing: false,
      initialState: CallSessionState.reconnecting,
      initialConnectedAt: DateTime.now().subtract(const Duration(seconds: 20)),
      engineProvider: () => _ThrowingResumeEngine(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    await session.beginResume();
    await tester.pump();

    expect(find.text('Unable to rejoin call'), findsOneWidget);
    await _pumpThroughAutoDismiss(tester);
  });

  testWidgets('non-string local display name extra falls back safely', (
    tester,
  ) async {
    final session = _buildSession(
      callType: CallType.video,
      initialState: CallSessionState.connected,
      extra: const <String, Object?>{
        CallDataExtraKeys.localDisplayName: 123,
      },
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-split-view')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('one-to-one-video-split-local-tap')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('one-to-one-video-primary-surface')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    session.dispose();
  });

  testWidgets('audio conference mode renders controls without camera', (
    tester,
  ) async {
    final session = _buildSession();
    addTearDown(session.dispose);
    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 1,
        participants: [
          CallParticipant(participantId: 'p-1', displayName: 'Ava'),
          CallParticipant(participantId: 'p-2', displayName: 'Milo'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey<String>('conference-view')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conference-controls-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-left-column')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-right-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-right-rail-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-controls-dock')),
      findsNothing,
    );

    final micButton = _actionButtonFinder('Mic');
    final speakerButton = _actionButtonFinder('Speaker');
    final camButton = _actionButtonFinder('Cam');
    final endButton = _actionButtonFinder('End');
    expect(micButton, findsOneWidget);
    expect(speakerButton, findsOneWidget);
    expect(camButton, findsNothing);
    expect(endButton, findsOneWidget);
  });

  testWidgets('video conference mode renders controls including camera', (
    tester,
  ) async {
    final session = _buildSession(callType: CallType.video);
    addTearDown(session.dispose);
    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 1,
        participants: [
          CallParticipant(participantId: 'p-1', displayName: 'Ava'),
          CallParticipant(participantId: 'p-2', displayName: 'Milo'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    final micButton = _actionButtonFinder('Mic');
    final speakerButton = _actionButtonFinder('Speaker');
    final camButton = _actionButtonFinder('Cam');
    final endButton = _actionButtonFinder('End');
    expect(micButton, findsOneWidget);
    expect(speakerButton, findsOneWidget);
    expect(camButton, findsOneWidget);
    expect(endButton, findsOneWidget);
  });

  testWidgets('conference layout keeps local panel in left column', (
    tester,
  ) async {
    final session = _buildSession(callType: CallType.video);
    addTearDown(session.dispose);
    session.updateConferenceState(
      const ConferenceState(
        updatedAtMs: 1,
        activeSpeakerId: 'p-1',
        participants: [
          CallParticipant(participantId: 'p-1', displayName: 'Ava'),
          CallParticipant(participantId: 'p-2', displayName: 'Milo'),
          CallParticipant(
            participantId: 'local',
            displayName: 'You',
            isLocal: true,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(session: session),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conference-primary-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-local-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('conference-right-rail-list')),
      findsOneWidget,
    );
    expect(find.text('Current Speaker'), findsOneWidget);
    expect(find.text('Current Speaker - Ava'), findsNothing);
  });
}

CallSession _buildSession({
  Future<void> Function(String callId)? acceptNative,
  Future<void> Function(String callId)? endNative,
  CallType callType = CallType.audio,
  CallSessionState initialState = CallSessionState.idle,
  Map<String, Object?>? extra,
}) {
  return CallSession(
    callData: CallData(
      callId: 'test-call-id',
      callerName: 'Ava',
      handle: '+1 555 0101',
      callType: callType,
      extra: extra,
    ),
    isOutgoing: false,
    initialState: initialState,
    acceptNative: acceptNative,
    endNative: endNative,
  );
}

void _pushCallScreen(
    GlobalKey<NavigatorState> navigatorKey, CallSession session) {
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => CallScreen(session: session),
    ),
  );
}

Future<void> _pumpThroughAutoDismiss(WidgetTester tester) async {
  await tester.pump(CallScreenTheme.autoDismissDelay);
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _actionButtonFinder(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is CallActionButton && widget.label == label,
  );
}

void _expectActionOrder({
  required WidgetTester tester,
  required List<String> labels,
}) {
  final leftPositions = labels
      .map((label) => tester.getTopLeft(_actionButtonFinder(label)).dx)
      .toList(growable: false);
  for (var index = 1; index < leftPositions.length; index += 1) {
    expect(leftPositions[index - 1], lessThan(leftPositions[index]));
  }
}

void _expectSquare(WidgetTester tester, Finder finder) {
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

class _ThrowingResumeEngine extends CallwaveEngine {
  @override
  Future<void> onAnswerCall(CallSession session) async {}

  @override
  Future<void> onStartCall(CallSession session) async {}

  @override
  Future<void> onResumeCall(CallSession session) async {
    throw StateError('resume failed');
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
