import Foundation
import UserNotifications

final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
  weak var forwardedDelegate: UNUserNotificationCenterDelegate?
  var responseHandler: ((UNNotificationResponse) -> Bool)?

  func install(center: UNUserNotificationCenter = .current()) {
    guard center.delegate !== self else { return }
    forwardedDelegate = center.delegate
    center.delegate = self
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if let forwardedDelegate,
       forwardedDelegate.responds(
        to: #selector(
          UNUserNotificationCenterDelegate.userNotificationCenter(
            _:willPresent:withCompletionHandler:
          )
        )
       ) {
      forwardedDelegate.userNotificationCenter?(
        center,
        willPresent: notification,
        withCompletionHandler: completionHandler
      )
      return
    }
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    _ = responseHandler?(response)
    if let forwardedDelegate,
       forwardedDelegate.responds(
        to: #selector(
          UNUserNotificationCenterDelegate.userNotificationCenter(
            _:didReceive:withCompletionHandler:
          )
        )
       ) {
      forwardedDelegate.userNotificationCenter?(
        center,
        didReceive: response,
        withCompletionHandler: completionHandler
      )
      return
    }
    completionHandler()
  }
}
