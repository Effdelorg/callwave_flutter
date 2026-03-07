import Foundation

struct CallPayload {
  let callId: String
  let callerName: String
  let handle: String
  let avatarUrl: String?
  let timeoutSeconds: Int
  let callType: String
  let extra: [String: Any]?
  let incomingAcceptStrategy: String

  init?(dictionary: [String: Any]) {
    guard let callId = dictionary["callId"] as? String else { return nil }
    self.callId = callId
    self.callerName = dictionary["callerName"] as? String ?? "Unknown"
    self.handle = dictionary["handle"] as? String ?? ""
    self.avatarUrl = dictionary["avatarUrl"] as? String
    self.timeoutSeconds = dictionary["timeoutSeconds"] as? Int ?? 30
    self.callType = dictionary["callType"] as? String ?? "audio"
    self.extra = dictionary["extra"] as? [String: Any]
    self.incomingAcceptStrategy =
      dictionary["incomingAcceptStrategy"] as? String ?? "openImmediately"
  }

  var dictionary: [String: Any] {
    [
      "callId": callId,
      "callerName": callerName,
      "handle": handle,
      "avatarUrl": avatarUrl as Any,
      "timeoutSeconds": timeoutSeconds,
      "callType": callType,
      "extra": extra as Any,
      "incomingAcceptStrategy": incomingAcceptStrategy,
    ]
  }

  func copy(extra: [String: Any]?) -> CallPayload {
    CallPayload(
      dictionary: [
        "callId": callId,
        "callerName": callerName,
        "handle": handle,
        "avatarUrl": avatarUrl as Any,
        "timeoutSeconds": timeoutSeconds,
        "callType": callType,
        "extra": extra as Any,
        "incomingAcceptStrategy": incomingAcceptStrategy,
      ]
    )!
  }

  init?(notificationUserInfo: [AnyHashable: Any]) {
    let extra = Self.extraFromNotificationUserInfo(notificationUserInfo)
    self.init(
      dictionary: [
        "callId": notificationUserInfo["callId"] as Any,
        "callerName": notificationUserInfo["callerName"] as Any,
        "handle": notificationUserInfo["handle"] as Any,
        "avatarUrl": notificationUserInfo["avatarUrl"] as Any,
        "timeoutSeconds": notificationUserInfo["timeoutSeconds"] as Any,
        "callType": notificationUserInfo["callType"] as Any,
        "extra": extra as Any,
        "incomingAcceptStrategy": notificationUserInfo["incomingAcceptStrategy"] as Any,
      ]
    )
  }

  var notificationUserInfo: [AnyHashable: Any] {
    var userInfo: [AnyHashable: Any] = [
      "callId": callId,
      "callerName": callerName,
      "handle": handle,
      "timeoutSeconds": timeoutSeconds,
      "callType": callType,
      "incomingAcceptStrategy": incomingAcceptStrategy,
    ]
    userInfo["avatarUrl"] = avatarUrl
    userInfo["extra"] = Self.extraJSONString(extra)
    return userInfo
  }

  var missedCallNotificationText: String {
    let customText = extra?["androidMissedCallNotificationText"] as? String
    let trimmed = customText?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return trimmed
    }
    return "\(callerName) (\(handle))"
  }

  private static func extraJSONString(_ extra: [String: Any]?) -> String? {
    guard let extra else { return nil }
    let sanitized = JSONValueSanitizer.sanitizeJSONObject(extra)
    guard JSONSerialization.isValidJSONObject(sanitized) else { return nil }
    let data = try? JSONSerialization.data(withJSONObject: sanitized)
    return data.flatMap { String(data: $0, encoding: .utf8) }
  }

  private static func extraFromNotificationUserInfo(
    _ userInfo: [AnyHashable: Any]
  ) -> [String: Any]? {
    guard let raw = userInfo["extra"] as? String, let data = raw.data(using: .utf8) else {
      return nil
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return nil
    }
    return dictionary
  }
}
