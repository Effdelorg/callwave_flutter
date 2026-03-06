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
}
