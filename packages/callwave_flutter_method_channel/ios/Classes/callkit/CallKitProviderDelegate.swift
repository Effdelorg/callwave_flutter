import Foundation
import CallKit
import AVFAudio

final class CallKitProviderDelegate: NSObject, CXProviderDelegate {
  var onAccept: ((UUID) -> Void)?
  var onEnd: ((UUID, CXCallEndedReason?) -> Void)?
  var onDidReset: (() -> Void)?

  func providerDidReset(_ provider: CXProvider) {
    onDidReset?()
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
    didDeactivate audioSession: AVAudioSession
  ) {
    // Media handling is owned by host app.
  }
}
