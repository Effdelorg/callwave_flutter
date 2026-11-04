import Foundation

// Run with the production Foundation-only readiness source; no simulator needed.
@main
struct OutgoingRingbackReadinessTests {
  static func main() {
    let now = Date(timeIntervalSince1970: 1000)
    let state = OutgoingRingbackReadiness()
    let call = "call"
    func prepare(_ controlled: Bool = true) -> String {
      state.prepare(callId: call, appControlled: controlled)
      return state.token(callId: call)!
    }
    func canStart(_ audio: Bool = true, _ date: Date? = nil) -> Bool {
      state.canStart(callId: call, audioActive: audio, now: date ?? now)
    }

    // Payload defaults/copies retain the new mode without changing old payloads.
    for raw in ["automatic", "appControlled", "unknown"] {
      let payload = CallPayload(dictionary: ["callId": call, "ringbackStartMode": raw])!
      let expected = raw == "appControlled" ? raw : "automatic"
      assert(payload.ringbackStartMode == expected)
      assert(payload.dictionary["ringbackStartMode"] as? String == expected)
      assert(payload.copy(extra: ["key": "value"]).ringbackStartMode == expected)
    }
    assert(CallPayload(dictionary: ["callId": call])!.ringbackStartMode == "automatic")
    assert(!CallPayload(dictionary: ["callId": call, "playRingback": false])!.playRingback)

    // Automatic mode preserves CallKit-only startup; visibility is irrelevant.
    var token = prepare(false)
    assert(!canStart()) // CallKit transaction completion is still pending.
    state.confirm(callId: call, token: token)
    assert(!canStart(false))
    assert(canStart())

    // All three prerequisites can arrive in any order.
    for permissionFirst in [true, false] {
      token = prepare()
      state.confirm(callId: call, token: token)
      if permissionFirst {
        assert(state.allow(callId: call, token: token))
        assert(!canStart())
        state.setVisible(callId: call, token: token, visible: true)
      } else {
        state.setVisible(callId: call, token: token, visible: true)
        assert(!canStart()) // No permission: no fallback, even much later.
        assert(!canStart(true, now.addingTimeInterval(10000)))
        assert(state.allow(callId: call, token: token))
      }
      assert(!canStart(false))
      assert(canStart())
      assert(!state.allow(callId: call, token: token)) // Duplicate permission.
      assert(!state.setVisible(callId: call, token: token, visible: true))
      state.setVisible(callId: call, token: token, visible: false)
      assert(!canStart()) // Hidden before CallKit activation.
      state.setVisible(callId: call, token: token, visible: true)
      assert(canStart()) // Permission survives hiding.
    }

    // No cap exists until actual successful playback, regardless of setup time.
    let actualStart = now.addingTimeInterval(500)
    let deadline = state.didStart(callId: call, seconds: 10, now: actualStart)!
    assert(deadline == actualStart.addingTimeInterval(10))
    assert(state.pendingToken(callId: call) == nil)
    assert(!state.allow(callId: call, token: token))
    assert(!state.setVisible(callId: call, token: token, visible: false))
    assert(canStart(true, actualStart.addingTimeInterval(9)))
    assert(state.didStart(callId: call, seconds: 999, now: actualStart.addingTimeInterval(9)) == deadline)
    assert(!canStart(true, deadline))
    assert(!canStart(true, deadline.addingTimeInterval(1)))

    // Replacement attempts reject old permissions, visibility, and completions.
    let old = token
    token = prepare()
    assert(token != old)
    state.confirm(callId: call, token: old)
    assert(!state.allow(callId: call, token: old))
    assert(!state.setVisible(callId: call, token: old, visible: true))
    assert(!canStart())
    state.confirm(callId: call, token: token)
    assert(state.allow(callId: call, token: token))
    assert(!canStart())
    state.setVisible(callId: call, token: token, visible: true)
    assert(canStart())

    // Connection/end/failure and engine teardown invalidate pending playback.
    for _ in 0..<3 {
      token = prepare()
      state.setVisible(callId: call, token: token, visible: true)
      state.invalidate(callId: call)
      assert(!state.allow(callId: call, token: token))
      assert(!canStart())
    }
    _ = prepare()
    state.clear()
    assert(!canStart())
    assert(state.token(callId: call) == nil)
    assert(OutgoingRingbackReadiness().token(callId: call) == nil) // Process restoration.
    print("OutgoingRingbackReadiness: all assertions passed")
  }
}
