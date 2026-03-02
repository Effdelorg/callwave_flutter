import Foundation

final class EventBufferStore {
  private let defaults: UserDefaults
  private var memoryQueue: [CallEventPayload] = []
  private var loaded = false

  private let maxEvents = 50
  private let maxAgeMs: Int64 = 10 * 60 * 1000
  private let key = "callwave_flutter_buffered_events"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func enqueue(_ event: CallEventPayload) {
    loadIfNeeded()
    pruneLocked()

    if memoryQueue.contains(where: { $0.dedupeKey == event.dedupeKey }) {
      return
    }

    memoryQueue.append(event)
    if memoryQueue.count > maxEvents {
      memoryQueue = Array(memoryQueue.suffix(maxEvents))
    }
    persistLocked()
  }

  func drain() -> [CallEventPayload] {
    loadIfNeeded()
    pruneLocked()
    let result = memoryQueue
    memoryQueue.removeAll(keepingCapacity: false)
    persistLocked()
    return result
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true

    guard let dataArray = defaults.array(forKey: key) as? [Data] else {
      return
    }

    memoryQueue = dataArray.compactMap { CallEventPayload.fromJSONData($0) }
  }

  private func pruneLocked() {
    let threshold = Int64(Date().timeIntervalSince1970 * 1000) - maxAgeMs
    memoryQueue = memoryQueue.filter { $0.timestampMs >= threshold }

    var seen = Set<String>()
    memoryQueue = memoryQueue.filter { event in
      if seen.contains(event.dedupeKey) { return false }
      seen.insert(event.dedupeKey)
      return true
    }

    if memoryQueue.count > maxEvents {
      memoryQueue = Array(memoryQueue.suffix(maxEvents))
    }
  }

  private func persistLocked() {
    guard !memoryQueue.isEmpty else {
      defaults.removeObject(forKey: key)
      return
    }

    let dataArray = memoryQueue.compactMap { $0.toJSONData() }
    defaults.set(dataArray, forKey: key)
  }
}
