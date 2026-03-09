import Foundation

final class IncomingCallStore {
  struct StoredIncomingCall {
    let payload: CallPayload
    let uuid: UUID
    let savedAtMs: Int64
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func save(payload: CallPayload, uuid: UUID) {
    var dictionary = payload.dictionary
    dictionary["uuid"] = uuid.uuidString
    dictionary["savedAtMs"] = Int64(Date().timeIntervalSince1970 * 1000)
    let sanitized = JSONValueSanitizer.sanitizeJSONObject(dictionary)
    guard JSONSerialization.isValidJSONObject(sanitized) else {
      defaults.removeObject(forKey: Self.key)
      return
    }
    let data = try? JSONSerialization.data(withJSONObject: sanitized)
    defaults.set(data, forKey: Self.key)
  }

  func restore() -> StoredIncomingCall? {
    guard let data = defaults.data(forKey: Self.key) else {
      return nil
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let payload = CallPayload(dictionary: dictionary),
      let uuidRaw = dictionary["uuid"] as? String,
      let uuid = UUID(uuidString: uuidRaw),
      let savedAtMs = (dictionary["savedAtMs"] as? NSNumber)?.int64Value
    else {
      return nil
    }
    return StoredIncomingCall(payload: payload, uuid: uuid, savedAtMs: savedAtMs)
  }

  func clear(callId: String? = nil) {
    if let callId, let snapshot = restore(), snapshot.payload.callId != callId {
      return
    }
    defaults.removeObject(forKey: Self.key)
  }

  private static let key = "callwave_flutter_incoming_call"
}
