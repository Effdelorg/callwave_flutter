import 'package:camera/camera.dart';
import 'package:callwave_flutter_example/example_camera_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

const CameraDescription _frontCamera = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('display aspect ratio', () {
    test('flips raw ratio in portrait orientation', () {
      final controller = ExampleCameraController();
      addTearDown(controller.dispose);

      final value = _cameraValue(
        previewSize: const Size(1920, 1080),
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      expect(
        controller.debugDisplayAspectRatioForValue(value),
        closeTo(9 / 16, 0.000001),
      );
    });

    test('keeps raw ratio in landscape orientation', () {
      final controller = ExampleCameraController();
      addTearDown(controller.dispose);

      final value = _cameraValue(
        previewSize: const Size(1920, 1080),
        deviceOrientation: DeviceOrientation.landscapeLeft,
      );

      expect(
        controller.debugDisplayAspectRatioForValue(value),
        closeTo(16 / 9, 0.000001),
      );
    });

    test('follows orientation priority used by CameraPreview', () {
      final controller = ExampleCameraController();
      addTearDown(controller.dispose);

      final withLockedCapture = _cameraValue(
        previewSize: const Size(1920, 1080),
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lockedCaptureOrientation: DeviceOrientation.portraitUp,
      );
      expect(
        controller.debugDisplayAspectRatioForValue(withLockedCapture),
        closeTo(9 / 16, 0.000001),
      );

      final withPausedPreview = _cameraValue(
        previewSize: const Size(1920, 1080),
        deviceOrientation: DeviceOrientation.landscapeLeft,
        lockedCaptureOrientation: DeviceOrientation.landscapeRight,
        previewPauseOrientation: DeviceOrientation.portraitDown,
      );
      expect(
        controller.debugDisplayAspectRatioForValue(withPausedPreview),
        closeTo(9 / 16, 0.000001),
      );

      final whileRecording = _cameraValue(
        previewSize: const Size(1920, 1080),
        deviceOrientation: DeviceOrientation.portraitUp,
        isRecordingVideo: true,
        recordingOrientation: DeviceOrientation.landscapeRight,
      );
      expect(
        controller.debugDisplayAspectRatioForValue(whileRecording),
        closeTo(16 / 9, 0.000001),
      );
    });

    test('returns null for invalid or uninitialized preview values', () {
      final controller = ExampleCameraController();
      addTearDown(controller.dispose);

      const uninitialized = CameraValue.uninitialized(_frontCamera);
      final invalidZero = _cameraValue(
        previewSize: const Size(0, 1080),
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      final invalidNaN = _cameraValue(
        previewSize: const Size(double.nan, 1080),
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      expect(controller.debugDisplayAspectRatioForValue(uninitialized), isNull);
      expect(controller.debugDisplayAspectRatioForValue(invalidZero), isNull);
      expect(controller.debugDisplayAspectRatioForValue(invalidNaN), isNull);
    });
  });

  test('moves listeners to latest camera controller and detaches on dispose',
      () async {
    final cameraOne = _TrackingCameraController(
      previewSize: const Size(1920, 1080),
      orientation: DeviceOrientation.portraitUp,
    );
    final cameraTwo = _TrackingCameraController(
      previewSize: const Size(1920, 1080),
      orientation: DeviceOrientation.landscapeLeft,
    );
    final createdControllers = <_TrackingCameraController>[
      cameraOne,
      cameraTwo,
    ];
    var createIndex = 0;

    final controller = ExampleCameraController(
      loadCameras: () async => const <CameraDescription>[_frontCamera],
      makeCameraController: (_) => createdControllers[createIndex++],
      requestPermission: (_) async => PermissionStatus.granted,
      openSystemSettings: () async => true,
    );
    addTearDown(controller.dispose);

    var notifyCount = 0;
    controller.addListener(() {
      notifyCount += 1;
    });

    await controller.attachSession('call-1');
    await controller.setCameraEnabled('call-1', true);

    expect(cameraOne.addListenerCount, 1);
    expect(controller.previewAspectRatio, closeTo(9 / 16, 0.000001));

    final notifyBeforeOrientationChange = notifyCount;
    cameraOne.emit(deviceOrientation: DeviceOrientation.landscapeLeft);
    expect(notifyCount, greaterThan(notifyBeforeOrientationChange));
    expect(controller.previewAspectRatio, closeTo(16 / 9, 0.000001));

    await controller.setCameraEnabled('call-1', true);
    expect(cameraOne.removeListenerCount, 1);
    expect(cameraOne.disposeCount, 1);
    expect(cameraTwo.addListenerCount, 1);
    expect(controller.previewAspectRatio, closeTo(16 / 9, 0.000001));

    controller.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(cameraTwo.removeListenerCount, 1);
    expect(cameraTwo.disposeCount, 1);
  });
}

CameraValue _cameraValue({
  required Size previewSize,
  required DeviceOrientation deviceOrientation,
  bool isRecordingVideo = false,
  DeviceOrientation? lockedCaptureOrientation,
  DeviceOrientation? previewPauseOrientation,
  DeviceOrientation? recordingOrientation,
}) {
  var value = const CameraValue.uninitialized(_frontCamera).copyWith(
    isInitialized: true,
    previewSize: previewSize,
    deviceOrientation: deviceOrientation,
    isRecordingVideo: isRecordingVideo,
  );
  if (lockedCaptureOrientation != null) {
    value = value.copyWith(
      lockedCaptureOrientation: Optional<DeviceOrientation>.of(
        lockedCaptureOrientation,
      ),
    );
  }
  if (previewPauseOrientation != null) {
    value = value.copyWith(
      previewPauseOrientation: Optional<DeviceOrientation>.of(
        previewPauseOrientation,
      ),
    );
  }
  if (recordingOrientation != null) {
    value = value.copyWith(
      recordingOrientation:
          Optional<DeviceOrientation>.of(recordingOrientation),
    );
  }
  return value;
}

class _TrackingCameraController extends CameraController {
  _TrackingCameraController({
    required this.previewSize,
    required this.orientation,
  }) : super(
          _frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

  final Size previewSize;
  final DeviceOrientation orientation;

  int addListenerCount = 0;
  int removeListenerCount = 0;
  int disposeCount = 0;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      previewSize: previewSize,
      deviceOrientation: orientation,
    );
  }

  void emit({
    Size? previewSize,
    DeviceOrientation? deviceOrientation,
    bool? isRecordingVideo,
    DeviceOrientation? lockedCaptureOrientation,
    DeviceOrientation? previewPauseOrientation,
    DeviceOrientation? recordingOrientation,
  }) {
    var next = value.copyWith(
      previewSize: previewSize ?? value.previewSize,
      deviceOrientation: deviceOrientation ?? value.deviceOrientation,
      isRecordingVideo: isRecordingVideo ?? value.isRecordingVideo,
    );
    if (lockedCaptureOrientation != null) {
      next = next.copyWith(
        lockedCaptureOrientation: Optional<DeviceOrientation>.of(
          lockedCaptureOrientation,
        ),
      );
    }
    if (previewPauseOrientation != null) {
      next = next.copyWith(
        previewPauseOrientation: Optional<DeviceOrientation>.of(
          previewPauseOrientation,
        ),
      );
    }
    if (recordingOrientation != null) {
      next = next.copyWith(
        recordingOrientation: Optional<DeviceOrientation>.of(
          recordingOrientation,
        ),
      );
    }
    value = next;
  }

  @override
  void addListener(VoidCallback listener) {
    addListenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removeListenerCount += 1;
    super.removeListener(listener);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await super.dispose();
  }
}
