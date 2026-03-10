import Foundation
import Flutter
import UserNotifications

public class CallwaveFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static var backgroundFlutterPluginRegistrant:
    ((FlutterPluginRegistry) -> Void)?

  private let eventBridge = EventStreamBridge(bufferStore: EventBufferStore())
  private let notificationDelegateProxy = NotificationDelegateProxy()
  private lazy var callManager = IOSCallManager(
    eventBridge: eventBridge,
    activeCallRegistry: ActiveCallRegistry()
  )
  private lazy var methodHandler = CallwaveMethodHandler(callManager: callManager)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CallwaveFlutterPlugin()
    instance.installNotificationHandling()

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

  /// Registers plugins for the headless Flutter engine used during background
  /// decline validation. Call from AppDelegate if your decline validator uses
  /// Flutter plugins (e.g. secure storage). Pass `nil` to clear.
  public static func setBackgroundFlutterPluginRegistrant(
    _ callback: ((FlutterPluginRegistry) -> Void)?
  ) {
    backgroundFlutterPluginRegistrant = callback
  }

  static func registerPluginsForBackgroundEngine(
    _ registry: FlutterPluginRegistry
  ) {
    if let backgroundFlutterPluginRegistrant {
      backgroundFlutterPluginRegistrant(registry)
      return
    }
    registerGeneratedPluginsForBackgroundEngine(registry)
  }

  private static func registerGeneratedPluginsForBackgroundEngine(
    _ registry: FlutterPluginRegistry
  ) {
    let selector = NSSelectorFromString("registerWithRegistry:")
    guard let generatedPluginRegistrantClass = generatedPluginRegistrantClass() else {
      return
    }
    let generatedPluginRegistrantObject = generatedPluginRegistrantClass as AnyObject
    guard generatedPluginRegistrantObject.responds(to: selector) else {
      return
    }
    _ = generatedPluginRegistrantObject.perform(selector, with: registry)
  }

  private static func generatedPluginRegistrantClass() -> AnyClass? {
    for candidate in generatedPluginRegistrantClassNames() {
      if let generatedPluginRegistrantClass = NSClassFromString(candidate) {
        return generatedPluginRegistrantClass
      }
    }
    return nil
  }

  private static func generatedPluginRegistrantClassNames() -> [String] {
    var candidates = ["GeneratedPluginRegistrant"]
    if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
      candidates.append("\(normalizedSwiftModuleName(bundleName)).GeneratedPluginRegistrant")
    }
    if let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
      candidates.append("\(normalizedSwiftModuleName(executableName)).GeneratedPluginRegistrant")
    }
    return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
  }

  private static func normalizedSwiftModuleName(_ value: String) -> String {
    let invalidCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted
    let components = value.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }
    return components.joined(separator: "_")
  }

  private func installNotificationHandling() {
    notificationDelegateProxy.responseHandler = { [weak self] response in
      self?.callManager.handleNotificationResponse(response: response) ?? false
    }
    notificationDelegateProxy.install()
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
