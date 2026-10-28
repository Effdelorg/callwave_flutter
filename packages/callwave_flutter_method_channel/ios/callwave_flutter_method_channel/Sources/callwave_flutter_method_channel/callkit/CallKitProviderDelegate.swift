import Foundation
import CallKit
import AVFAudio

final class CallKitProviderDelegate: NSObject, CXProviderDelegate {
  var onStart: ((UUID) -> Void)?
  var onAccept: ((UUID) -> Void)?
  var onEnd: ((UUID, CXCallEndedReason?) -> Void)?
  var onDidReset: (() -> Void)?
  var onAudioSessionActivated: (() -> Void)?
  var onAudioSessionDeactivated: (() -> Void)?

  func providerDidReset(_ provider: CXProvider) {
    onDidReset?()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    onStart?(action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    onAccept?(action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    onEnd?(action.callUUID, nil)
    action.fulfill()
  }

  func provider(
    _ provider: CXProvider,
    didActivate audioSession: AVAudioSession
  ) {
    // Only used for the outgoing ringback tone (opt out with `playRingback: false`);
    // other media is owned by host app.
    onAudioSessionActivated?()
  }

  func provider(
    _ provider: CXProvider,
    didDeactivate audioSession: AVAudioSession
  ) {
    // Media handling is owned by host app.
    onAudioSessionDeactivated?()
  }
}
