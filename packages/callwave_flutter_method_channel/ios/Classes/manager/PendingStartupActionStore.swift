import Foundation

final class PendingStartupActionStore {
  private let defaults: UserDefaults
  private let key = "callwave_flutter_pending_startup_action"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func save(type: String, payload: CallPayload) {
    var dictionary: [String: Any] = [
      "startupActionType": type,
      "callId": payload.callId,
      "callerName": payload.callerName,
      "handle": payload.handle,
      "callType": payload.callType,
    ]
    dictionary["avatarUrl"] = payload.avatarUrl
    dictionary["extra"] = payload.extra.map(JSONValueSanitizer.sanitizeJSONObject)
    guard JSONSerialization.isValidJSONObject(dictionary) else { return }
    let data = try? JSONSerialization.data(withJSONObject: dictionary)
    defaults.set(data, forKey: key)
  }

  func take() -> [String: Any]? {
    guard let data = defaults.data(forKey: key) else { return nil }
    defaults.removeObject(forKey: key)
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return nil
    }
    return dictionary
  }
}
