import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

enum ExampleCameraState {
  idle,
  requestingPermission,
  ready,
  errorPermissionDenied,
  errorUnavailable,
}

/// Abstract handle for camera preview used by the example video call UI.
abstract class ExampleCameraHandle extends ChangeNotifier {
  ExampleCameraState get state;
  bool get isPreviewReady;

  /// Display aspect ratio of the preview (width/height) after orientation
  /// correction, or null if not ready.
  double? get previewAspectRatio;
  String? get errorMessage;

  Future<void> attachSession(String callId);
  Future<void> detachSession(String callId);
  Future<void> setCameraEnabled(String callId, bool enabled);
  Future<void> retryPermission(String callId);
  Future<void> openSystemSettings();

  Widget buildPreview({Key? key});
}

typedef LoadCameras = Future<List<CameraDescription>> Function();
typedef MakeCameraController = CameraController Function(
  CameraDescription description,
);
typedef RequestPermission = Future<PermissionStatus> Function(
  Permission permission,
);
typedef OpenSystemSettings = Future<bool> Function();

class ExampleCameraController extends ExampleCameraHandle
    with WidgetsBindingObserver {
  ExampleCameraController({
    LoadCameras? loadCameras,
    MakeCameraController? makeCameraController,
    RequestPermission? requestPermission,
    OpenSystemSettings? openSystemSettings,
  })  : _loadCameras = loadCameras ?? availableCameras,
        _makeCameraController =
            makeCameraController ?? _defaultCameraController,
        _requestPermission = requestPermission ?? _defaultRequestPermission,
        _openSystemSettings = openSystemSettings ?? openAppSettings {
    WidgetsBinding.instance.addObserver(this);
  }

  final LoadCameras _loadCameras;
  final MakeCameraController _makeCameraController;
  final RequestPermission _requestPermission;
  final OpenSystemSettings _openSystemSettings;
  final Set<String> _attachedCallIds = <String>{};
  final Map<String, bool> _cameraEnabledByCallId = <String, bool>{};

  CameraController? _cameraController;
  ExampleCameraState _state = ExampleCameraState.idle;
  String? _errorMessage;
  int _operationVersion = 0;
  bool _disposed = false;

  @override
  ExampleCameraState get state => _state;

  @override
  bool get isPreviewReady =>
      _state == ExampleCameraState.ready &&
      _cameraController != null &&
      _cameraController!.value.isInitialized;

  @override
  double? get previewAspectRatio {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    return _displayAspectRatio(controller.value);
  }

  @override
  String? get errorMessage => _errorMessage;

  bool get _hasAnyCameraEnabled =>
      _cameraEnabledByCallId.values.any((enabled) => enabled);

  static CameraController _defaultCameraController(
    CameraDescription description,
  ) {
    return CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );
  }

  static Future<PermissionStatus> _defaultRequestPermission(
    Permission permission,
  ) {
    return permission.request();
  }

  @override
  Future<void> attachSession(String callId) async {
    if (_disposed) {
      return;
    }
    _attachedCallIds.add(callId);
    _cameraEnabledByCallId.putIfAbsent(callId, () => false);
  }

  @override
  Future<void> detachSession(String callId) async {
    if (_disposed) {
      return;
    }
    _attachedCallIds.remove(callId);
    _cameraEnabledByCallId.remove(callId);
    if (_hasAnyCameraEnabled) {
      return;
    }
    await _stopPreview();
  }

  @override
  Future<void> setCameraEnabled(String callId, bool enabled) async {
    if (_disposed) {
      return;
    }
    _attachedCallIds.add(callId);
    _cameraEnabledByCallId[callId] = enabled;
    if (!enabled && _hasAnyCameraEnabled) {
      return;
    }
    if (enabled) {
      await _startPreview();
      return;
    }
    await _stopPreview();
  }

  @override
  Future<void> retryPermission(String callId) async {
    if (_disposed) {
      return;
    }
    _attachedCallIds.add(callId);
    _cameraEnabledByCallId[callId] = true;
    await _startPreview();
  }

  @override
  Future<void> openSystemSettings() async {
    await _openSystemSettings();
  }

  @override
  Widget buildPreview({Key? key}) {
    final controller = _cameraController;
    if (controller == null || !isPreviewReady) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      key: key,
      child: CameraPreview(controller),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_hasAnyCameraEnabled) {
        unawaited(_startPreview());
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopPreview());
    }
  }

  Future<void> _startPreview() async {
    final operation = ++_operationVersion;
    _setState(ExampleCameraState.requestingPermission);
    _errorMessage = null;
    notifyListeners();

    final cameraPermission = await _requestPermission(Permission.camera);
    final microphonePermission = await _requestPermission(
      Permission.microphone,
    );
    if (!_isCurrent(operation)) {
      return;
    }
    if (!cameraPermission.isGranted || !microphonePermission.isGranted) {
      await _disposeController();
      _setError(
        ExampleCameraState.errorPermissionDenied,
        'Camera permission is needed for video preview.',
      );
      return;
    }

    List<CameraDescription> cameras;
    try {
      cameras = await _loadCameras();
    } catch (_) {
      if (!_isCurrent(operation)) {
        return;
      }
      await _disposeController();
      _setError(
        ExampleCameraState.errorUnavailable,
        'Camera is unavailable on this device.',
      );
      return;
    }

    if (!_isCurrent(operation)) {
      return;
    }

    if (cameras.isEmpty) {
      await _disposeController();
      _setError(
        ExampleCameraState.errorUnavailable,
        'No camera was found on this device.',
      );
      return;
    }

    final selected = _selectPreferredCamera(cameras);
    CameraController? created;
    try {
      created = _makeCameraController(selected);
      await created.initialize();
    } catch (_) {
      await created?.dispose();
      if (!_isCurrent(operation)) {
        return;
      }
      await _disposeController();
      _setError(
        ExampleCameraState.errorUnavailable,
        'Camera failed to start. Try again.',
      );
      return;
    }

    if (!_isCurrent(operation)) {
      await created.dispose();
      return;
    }

    await _replaceController(created);
    _setState(ExampleCameraState.ready);
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _stopPreview() async {
    _operationVersion += 1;
    await _disposeController();
    if (_state != ExampleCameraState.idle || _errorMessage != null) {
      _setState(ExampleCameraState.idle);
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<void> _replaceController(CameraController next) async {
    final previous = _cameraController;
    previous?.removeListener(_onCameraValueChanged);
    _cameraController = next;
    next.addListener(_onCameraValueChanged);
    await previous?.dispose();
  }

  Future<void> _disposeController() async {
    final controller = _cameraController;
    _cameraController = null;
    controller?.removeListener(_onCameraValueChanged);
    await controller?.dispose();
  }

  void _onCameraValueChanged() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @visibleForTesting
  double? debugDisplayAspectRatioForValue(CameraValue value) {
    return _displayAspectRatio(value);
  }

  double? _displayAspectRatio(CameraValue value) {
    if (!value.isInitialized || value.previewSize == null) {
      return null;
    }
    final rawAspectRatio = value.aspectRatio;
    if (!rawAspectRatio.isFinite || rawAspectRatio <= 0) {
      return null;
    }
    final orientation = _applicableOrientation(value);
    if (_isLandscape(orientation)) {
      return rawAspectRatio;
    }
    return 1 / rawAspectRatio;
  }

  DeviceOrientation _applicableOrientation(CameraValue value) {
    if (value.isRecordingVideo) {
      return value.recordingOrientation ?? value.deviceOrientation;
    }
    return value.previewPauseOrientation ??
        value.lockedCaptureOrientation ??
        value.deviceOrientation;
  }

  bool _isLandscape(DeviceOrientation orientation) {
    return orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
  }

  CameraDescription _selectPreferredCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return camera;
      }
    }
    return cameras.first;
  }

  bool _isCurrent(int operation) =>
      !_disposed && operation == _operationVersion;

  void _setState(ExampleCameraState next) {
    _state = next;
  }

  void _setError(ExampleCameraState next, String message) {
    _state = next;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    super.dispose();
  }
}
