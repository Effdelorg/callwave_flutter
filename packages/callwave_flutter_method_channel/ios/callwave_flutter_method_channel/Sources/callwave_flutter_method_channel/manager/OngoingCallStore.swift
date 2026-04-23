import Foundation

final class OngoingCallStore {
  struct StoredOngoingCall {
    let payload: CallPayload
    let eventType: String
    let connectedAtMs: Int64?
    let uuid: UUID?
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func save(
    payload: CallPayload,
    eventType: String,
    connectedAtMs: Int64?,
    uuid: UUID?
  ) {
    var dictionary = payload.dictionary
    dictionary["eventType"] = eventType
    dictionary["connectedAtMs"] = connectedAtMs as Any
    dictionary["uuid"] = uuid?.uuidString as Any
    let sanitized = JSONValueSanitizer.sanitizeJSONObject(dictionary)
    guard JSONSerialization.isValidJSONObject(sanitized) else {
      defaults.removeObject(forKey: Self.key)
      return
    }
    let data = try? JSONSerialization.data(withJSONObject: sanitized)
    defaults.set(data, forKey: Self.key)
  }

  func updateConnectedAt(callId: String, connectedAtMs: Int64) {
    guard let snapshot = restore(), snapshot.payload.callId == callId else {
      return
    }
    save(
      payload: snapshot.payload,
      eventType: snapshot.eventType,
      connectedAtMs: connectedAtMs,
      uuid: snapshot.uuid
    )
  }

  func restore() -> StoredOngoingCall? {
    guard let data = defaults.data(forKey: Self.key) else {
      return nil
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return nil
    }
    guard let payload = CallPayload(dictionary: dictionary) else {
      return nil
    }
    guard let eventType = dictionary["eventType"] as? String, !eventType.isEmpty else {
      return nil
    }
    let connectedAtMs = (dictionary["connectedAtMs"] as? NSNumber)?.int64Value
    let uuid = (dictionary["uuid"] as? String).flatMap(UUID.init(uuidString:))
    return StoredOngoingCall(
      payload: payload,
      eventType: eventType,
      connectedAtMs: connectedAtMs,
      uuid: uuid
    )
  }

  func clear(callId: String? = nil) {
    if let callId, let snapshot = restore(), snapshot.payload.callId != callId {
      return
    }
    defaults.removeObject(forKey: Self.key)
  }

  private static let key = "callwave_flutter_ongoing_call"
}
