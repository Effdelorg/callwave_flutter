import Foundation
import UserNotifications

final class MissedCallNotificationManager {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func registerCategories() {
    let callbackAction = UNNotificationAction(
      identifier: Self.callbackActionIdentifier,
      title: "Call Back",
      options: [.foreground]
    )
    let category = UNNotificationCategory(
      identifier: Self.categoryIdentifier,
      actions: [callbackAction],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    center.getNotificationCategories { existing in
      var categories = existing
      categories.insert(category)
      self.center.setNotificationCategories(categories)
    }
  }

  func requestPermission(completion: @escaping (Bool) -> Void) {
    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      completion(granted)
    }
  }

  func showMissedCall(payload: CallPayload) {
    let content = UNMutableNotificationContent()
    content.title = "Missed call"
    content.body = payload.missedCallNotificationText
    content.sound = .default
    content.categoryIdentifier = Self.categoryIdentifier
    content.userInfo = payload.notificationUserInfo

    let request = UNNotificationRequest(
      identifier: requestIdentifier(for: payload.callId),
      content: content,
      trigger: nil
    )
    center.add(request)
  }

  func dismissMissedCall(callId: String) {
    let identifier = requestIdentifier(for: callId)
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }

  func payload(from response: UNNotificationResponse) -> CallPayload? {
    guard response.notification.request.content.categoryIdentifier == Self.categoryIdentifier else {
      return nil
    }
    return CallPayload(notificationUserInfo: response.notification.request.content.userInfo)
  }

  static let categoryIdentifier = "callwave_flutter_missed_call"
  static let callbackActionIdentifier = "callwave_flutter_callback"

  private func requestIdentifier(for callId: String) -> String {
    "callwave_flutter_missed_\(callId)"
  }
}
