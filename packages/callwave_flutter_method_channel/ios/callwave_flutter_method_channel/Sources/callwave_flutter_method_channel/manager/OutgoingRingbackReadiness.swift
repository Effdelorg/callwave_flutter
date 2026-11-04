import Foundation

/// Main-queue-only attempt state. Not persisted, so restored calls stay silent.
final class OutgoingRingbackReadiness {
  private struct Attempt {
    let id = UUID().uuidString
    let appControlled: Bool
    var confirmed = false
    var allowed = false
    var visible = false
    var deadline: Date?
  }
  private var attempts: [String: Attempt] = [:]

  func prepare(callId: String, appControlled: Bool) {
    attempts[callId] = Attempt(appControlled: appControlled)
  }
  func token(callId: String) -> String? { attempts[callId]?.id }
  func pendingToken(callId: String) -> String? {
    guard let attempt = attempts[callId], attempt.deadline == nil else { return nil }
    return attempt.id
  }
  func confirm(callId: String, token: String) {
    guard attempts[callId]?.id == token else { return }
    attempts[callId]?.confirmed = true
  }
  func allow(callId: String, token: String) -> Bool {
    guard let attempt = attempts[callId], attempt.id == token,
      attempt.deadline == nil, !attempt.allowed else { return false }
    attempts[callId]?.allowed = true
    return true
  }
  @discardableResult
  func setVisible(callId: String, token: String, visible: Bool) -> Bool {
    guard let attempt = attempts[callId], attempt.id == token,
      attempt.deadline == nil, attempt.visible != visible else { return false }
    attempts[callId]?.visible = visible
    return true
  }
  func canStart(callId: String, audioActive: Bool, now: Date = Date()) -> Bool {
    guard audioActive, let attempt = attempts[callId], attempt.confirmed else { return false }
    if let deadline = attempt.deadline { return now < deadline }
    return !attempt.appControlled || (attempt.allowed && attempt.visible)
  }
  /// Called only after successful playback. Restarts never extend the deadline.
  func didStart(callId: String, seconds: Int, now: Date = Date()) -> Date? {
    guard var attempt = attempts[callId] else { return nil }
    if attempt.deadline == nil {
      attempt.deadline = now.addingTimeInterval(TimeInterval(seconds))
      attempts[callId] = attempt
    }
    return attempt.deadline
  }
  func invalidate(callId: String) { attempts.removeValue(forKey: callId) }
  func clear() { attempts.removeAll() }
}
