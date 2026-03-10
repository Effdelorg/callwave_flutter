import Foundation

final class BackgroundValidatorRegistrationStore {
  struct Registration {
    let backgroundDispatcherHandle: Int64
    let backgroundAcceptCallbackHandle: Int64?
    let backgroundDeclineCallbackHandle: Int64?
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> Registration? {
    guard defaults.object(forKey: Self.dispatcherKey) != nil else {
      return nil
    }

    let dispatcherHandle = defaults.integer(forKey: Self.dispatcherKey)
    let acceptCallbackHandle = positiveInt64Value(forKey: Self.acceptKey)
    let declineCallbackHandle = positiveInt64Value(forKey: Self.declineKey)

    guard dispatcherHandle > 0 else {
      clear()
      return nil
    }
    guard acceptCallbackHandle != nil || declineCallbackHandle != nil else {
      clear()
      return nil
    }

    return Registration(
      backgroundDispatcherHandle: Int64(dispatcherHandle),
      backgroundAcceptCallbackHandle: acceptCallbackHandle,
      backgroundDeclineCallbackHandle: declineCallbackHandle
    )
  }

  func save(
    backgroundDispatcherHandle: Int64,
    backgroundAcceptCallbackHandle: Int64?,
    backgroundDeclineCallbackHandle: Int64?
  ) {
    defaults.set(backgroundDispatcherHandle, forKey: Self.dispatcherKey)
    if let backgroundAcceptCallbackHandle, backgroundAcceptCallbackHandle > 0 {
      defaults.set(backgroundAcceptCallbackHandle, forKey: Self.acceptKey)
    } else {
      defaults.removeObject(forKey: Self.acceptKey)
    }
    if let backgroundDeclineCallbackHandle, backgroundDeclineCallbackHandle > 0 {
      defaults.set(backgroundDeclineCallbackHandle, forKey: Self.declineKey)
    } else {
      defaults.removeObject(forKey: Self.declineKey)
    }
  }

  func clear() {
    defaults.removeObject(forKey: Self.dispatcherKey)
    defaults.removeObject(forKey: Self.acceptKey)
    defaults.removeObject(forKey: Self.declineKey)
  }

  private static let dispatcherKey = "callwave_flutter_background_dispatcher_handle"
  private static let acceptKey = "callwave_flutter_background_accept_callback_handle"
  private static let declineKey = "callwave_flutter_background_decline_callback_handle"

  private func positiveInt64Value(forKey key: String) -> Int64? {
    guard defaults.object(forKey: key) != nil else {
      return nil
    }
    let value = defaults.integer(forKey: key)
    return value > 0 ? Int64(value) : nil
  }
}
