import Foundation
import Flutter

public class CallwaveFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let eventBridge = EventStreamBridge(bufferStore: EventBufferStore())
  private lazy var callManager = IOSCallManager(
    eventBridge: eventBridge,
    activeCallRegistry: ActiveCallRegistry()
  )
  private lazy var methodHandler = CallwaveMethodHandler(callManager: callManager)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CallwaveFlutterPlugin()

    let methodChannel = FlutterMethodChannel(
      name: "callwave_flutter/methods",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: "callwave_flutter/events",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    methodHandler.handle(call, result: result)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventBridge.attach(events)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventBridge.detach()
    return nil
  }
}
