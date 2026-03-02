import Foundation

final class ActiveCallRegistry {
  private var activeCalls: Set<String> = []

  func tryStart(callId: String) -> Bool {
    if activeCalls.isEmpty || activeCalls.contains(callId) {
      activeCalls.insert(callId)
      return true
    }
    return false
  }

  func remove(callId: String) {
    activeCalls.remove(callId)
  }

  func activeCallIds() -> [String] {
    Array(activeCalls)
  }
}
