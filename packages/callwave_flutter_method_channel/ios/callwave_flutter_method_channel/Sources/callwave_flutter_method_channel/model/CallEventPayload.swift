import Foundation

struct CallEventPayload {
  let callId: String
  let type: String
  let timestampMs: Int64
  let extra: [String: Any]?

  var dedupeKey: String {
    let bucket = timestampMs / 1000
    return "\(callId)|\(type)|\(bucket)"
  }

  func toDictionary() -> [String: Any] {
    var dictionary: [String: Any] = [
      "callId": callId,
      "type": type,
      "timestampMs": timestampMs,
    ]
    if let extra {
      dictionary["extra"] = extra
    }
    return dictionary
  }

  func toJSONData() -> Data? {
    try? JSONSerialization.data(withJSONObject: toDictionary(), options: [])
  }

  static func fromJSONData(_ data: Data) -> CallEventPayload? {
    guard
      let raw = try? JSONSerialization.jsonObject(with: data, options: []),
      let dictionary = raw as? [String: Any],
      let callId = dictionary["callId"] as? String,
      let type = dictionary["type"] as? String
    else {
      return nil
    }

    let timestampNumber = dictionary["timestampMs"] as? NSNumber
    let timestampMs = timestampNumber?.int64Value ?? 0
    guard timestampMs > 0 else { return nil }

    return CallEventPayload(
      callId: callId,
      type: type,
      timestampMs: timestampMs,
      extra: dictionary["extra"] as? [String: Any]
    )
  }

  static func now(callId: String, type: String, extra: [String: Any]?) -> CallEventPayload {
    CallEventPayload(
      callId: callId,
      type: type,
      timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
      extra: extra
    )
  }
}
