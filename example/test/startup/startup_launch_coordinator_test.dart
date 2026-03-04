import 'package:callwave_flutter_example/startup/startup_launch_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to demo mode with no startup signal', () {
    final coordinator = StartupLaunchCoordinator();

    expect(coordinator.launchMode, StartupLaunchMode.demo);
    expect(coordinator.startupCallRequested, isFalse);
    expect(coordinator.startupResolutionComplete, isFalse);
  });

  test('accepted signal moves coordinator into loading mode', () {
    final coordinator = StartupLaunchCoordinator();

    coordinator.markAcceptedSignal();

    expect(coordinator.startupCallRequested, isTrue);
    expect(coordinator.launchMode, StartupLaunchMode.loading);
  });

  test('shouldOpenAsStartupJoinedCall only during unresolved startup',
      () async {
    final coordinator = StartupLaunchCoordinator(
      checkInterval: const Duration(milliseconds: 1),
      maxWait: const Duration(milliseconds: 2),
    );

    expect(
      coordinator.shouldOpenAsStartupJoinedCall(hasOpenCallScreens: false),
      isFalse,
    );

    coordinator.markAcceptedSignal();
    expect(
      coordinator.shouldOpenAsStartupJoinedCall(hasOpenCallScreens: false),
      isTrue,
    );

    await coordinator.completeStartupResolution(
      restoreActiveCalls: ({required bool force}) async {},
      hasJoinSignal: () => false,
    );

    expect(coordinator.startupResolutionComplete, isTrue);
    expect(
      coordinator.shouldOpenAsStartupJoinedCall(hasOpenCallScreens: false),
      isFalse,
    );
  });

  test('openStartupJoinedCall pins joined call id and mode', () {
    final coordinator = StartupLaunchCoordinator();

    coordinator.openStartupJoinedCall('c-1');

    expect(coordinator.launchMode, StartupLaunchMode.startupJoinedCall);
    expect(coordinator.startupJoinedCallId, 'c-1');
    expect(coordinator.isStartupJoinedCall('c-1'), isTrue);
    expect(coordinator.isStartupJoinedCall('c-2'), isFalse);
  });

  test('showDemoMode clears joined call id', () {
    final coordinator = StartupLaunchCoordinator();
    coordinator.openStartupJoinedCall('c-1');

    coordinator.showDemoMode();

    expect(coordinator.launchMode, StartupLaunchMode.demo);
    expect(coordinator.startupJoinedCallId, isNull);
  });
}
