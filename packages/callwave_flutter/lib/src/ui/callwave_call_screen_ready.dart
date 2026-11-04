import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../engine/call_session.dart';

/// Reports readiness after the call screen paints and its entrance completes.
///
/// Wrap custom call routes, including pre-routed startup screens. For navigation
/// without a [ModalRoute], explicitly use [CallSession.setCallScreenVisible].
/// Nested wrappers for the same session delegate to the innermost screen.
class CallwaveCallScreenReady extends StatefulWidget {
  const CallwaveCallScreenReady({
    required this.session,
    required this.child,
    this.entranceAnimation,
    super.key,
  });

  final CallSession session;
  final Widget child;

  /// Optional content entrance animation, in addition to the route transition.
  final Animation<double>? entranceAnimation;

  @override
  State<CallwaveCallScreenReady> createState() =>
      _CallwaveCallScreenReadyState();
}

class _CallwaveCallScreenReadyState extends State<CallwaveCallScreenReady>
    with WidgetsBindingObserver {
  final _children = <_CallwaveCallScreenReadyState>{};
  _CallwaveCallScreenReadyState? _parent;
  CallSession? _observedSession;
  ModalRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  RenderProxyBox? _paintObserver;
  bool _painted = false;
  bool _scheduled = false;
  bool _disposed = false;

  bool get _ownsVisibility => _children.isEmpty;
  bool get _needsObservation =>
      !_disposed &&
      _ownsVisibility &&
      widget.session.needsOutgoingScreenReadiness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.entranceAnimation?.addStatusListener(_onAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(covariant CallwaveCallScreenReady oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entranceAnimation, widget.entranceAnimation)) {
      oldWidget.entranceAnimation?.removeStatusListener(_onAnimationStatus);
      widget.entranceAnimation?.addStatusListener(_onAnimationStatus);
    }
    if (!identical(oldWidget.session, widget.session)) {
      if (_ownsVisibility) oldWidget.session.setCallScreenVisible(false);
      _stopObserving();
    }
    _bind();
  }

  void _bind() {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_ReadinessOwner>();
    final parent = identical(inherited?.session, widget.session)
        ? inherited?.owner
        : null;
    if (!identical(_parent, parent)) {
      _parent?._removeChild(this);
      _parent = parent;
      _parent?._addChild(this);
    }
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    _route = ModalRoute.of(context);
    _routeAnimation = _route?.animation;
    _routeAnimation?.addStatusListener(_onAnimationStatus);
    _invalidateVisibility();
  }

  void _addChild(_CallwaveCallScreenReadyState child) {
    _children.add(child);
    widget.session.setCallScreenVisible(false);
    _syncObservation();
  }

  void _removeChild(_CallwaveCallScreenReadyState child) {
    _children.remove(child);
    if (!_disposed) _invalidateVisibility();
  }

  void _stopObserving() {
    _observedSession?.removeListener(_onSessionChanged);
    _observedSession = null;
  }

  void _syncObservation() {
    if (!_needsObservation) {
      _stopObserving();
    } else if (!identical(_observedSession, widget.session)) {
      _stopObserving();
      _observedSession = widget.session;
      _observedSession!.addListener(_onSessionChanged);
    }
  }

  void _onSessionChanged() {
    _syncObservation();
    if (_needsObservation) _requestPaint();
  }

  void _requestPaint() {
    if (_paintObserver?.attached == true) _paintObserver!.markNeedsPaint();
  }

  // Check ancestors too: a current route can contain an Offstage or transparent
  // subtree without changing ModalRoute.isCurrent or ModalRoute.offstage.
  bool get _canShow {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_ownsVisibility ||
        _route == null ||
        !_route!.isCurrent ||
        _route!.offstage ||
        (_routeAnimation != null && !_routeAnimation!.isCompleted) ||
        (widget.entranceAnimation != null &&
            !widget.entranceAnimation!.isCompleted) ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed))
      return false;
    for (
      var ancestor = _parent;
      ancestor != null;
      ancestor = ancestor._parent
    ) {
      final entrance = ancestor.widget.entranceAnimation;
      if (entrance != null && !entrance.isCompleted) return false;
    }
    RenderObject? child = _paintObserver;
    if (child == null || !child.attached) return false;
    RenderObject current = child;
    for (var parent = current.parent; parent != null; parent = current.parent) {
      if (!parent.paintsChild(current)) return false;
      current = parent;
    }
    return true;
  }

  void _onAnimationStatus(AnimationStatus _) => _invalidateVisibility();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _invalidateVisibility();

  void _invalidateVisibility() {
    if (_disposed) return;
    for (final child in _children.toList(growable: false)) {
      child._invalidateVisibility();
    }
    _painted = false;
    if (_ownsVisibility) widget.session.setCallScreenVisible(false);
    _syncObservation();
    if (_needsObservation) _requestPaint();
  }

  void _onPaint() {
    _syncObservation();
    if (!_needsObservation) return;
    _painted = true;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_needsObservation) return;
      widget.session.setCallScreenVisible(
        _painted && _canShow,
        isStillVisible: () => mounted && _painted && _canShow,
      );
      _syncObservation();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _stopObserving();
    _routeAnimation?.removeStatusListener(_onAnimationStatus);
    widget.entranceAnimation?.removeStatusListener(_onAnimationStatus);
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsVisibility) widget.session.setCallScreenVisible(false);
    _parent?._removeChild(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ReadinessOwner(
    session: widget.session,
    owner: this,
    child: _ScreenPaintObserver(
      onCreated: (observer) => _paintObserver = observer,
      onPaint: _onPaint,
      child: widget.child,
    ),
  );
}

class _ReadinessOwner extends InheritedWidget {
  const _ReadinessOwner({
    required this.session,
    required this.owner,
    required super.child,
  });
  final CallSession session;
  final _CallwaveCallScreenReadyState owner;

  @override
  bool updateShouldNotify(_ReadinessOwner oldWidget) =>
      !identical(session, oldWidget.session) ||
      !identical(owner, oldWidget.owner);
}

class _ScreenPaintObserver extends SingleChildRenderObjectWidget {
  const _ScreenPaintObserver({
    required this.onCreated,
    required this.onPaint,
    required super.child,
  });
  final ValueChanged<RenderProxyBox> onCreated;
  final VoidCallback onPaint;

  @override
  RenderProxyBox createRenderObject(BuildContext context) {
    final observer = _ScreenPaintRenderObject(onPaint);
    onCreated(observer);
    return observer;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _ScreenPaintRenderObject renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _ScreenPaintRenderObject extends RenderProxyBox {
  _ScreenPaintRenderObject(this.onPaint);
  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
