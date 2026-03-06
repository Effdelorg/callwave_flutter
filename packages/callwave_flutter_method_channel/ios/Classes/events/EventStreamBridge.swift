import Foundation
import Flutter

final class EventStreamBridge {
  private var sink: FlutterEventSink?
  private let bufferStore: EventBufferStore

  init(bufferStore: EventBufferStore) {
    self.bufferStore = bufferStore
  }

  func attach(_ sink: @escaping FlutterEventSink) {
    self.sink = sink
    flushBuffered()
  }

  func detach() {
    sink = nil
  }

  var hasListener: Bool {
    sink != nil
  }

  func emit(_ event: CallEventPayload) {
    guard let sink else {
      bufferStore.enqueue(event)
      return
    }

    sink(event.toDictionary())
  }

  private func flushBuffered() {
    guard let sink else { return }
    let events = bufferStore.drain()
    for event in events {
      sink(event.toDictionary())
    }
  }
}
