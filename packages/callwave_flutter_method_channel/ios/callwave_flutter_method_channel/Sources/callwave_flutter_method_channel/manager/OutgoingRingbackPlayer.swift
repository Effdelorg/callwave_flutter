import AVFAudio
import Foundation

/// Plays a synthesized ringback tone (440 Hz + 480 Hz, 2s on / 4s off) while an
/// outgoing call waits to be answered.
///
/// Must be used on the main queue, and only while CallKit has the call's audio
/// session activated. Never activates or deactivates the audio session itself.
final class OutgoingRingbackPlayer {
  private static let sampleRate: Double = 44_100
  private static let toneFrequencies: [Double] = [440, 480]
  private static let toneSeconds: Double = 2
  private static let cycleSeconds: Double = 6
  private static let fadeSeconds: Double = 0.01
  private static let amplitude: Float = 0.15

  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var activeCallId: String?
  private var configurationObserver: NSObjectProtocol?

  func start(callId: String) {
    if activeCallId == callId, engine != nil {
      return
    }
    stop()
    guard
      let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
      let buffer = Self.makeCycleBuffer(format: format)
    else {
      return
    }

    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    do {
      engine.prepare()
      try engine.start()
    } catch {
      engine.detach(playerNode)
      return
    }
    playerNode.play()

    self.engine = engine
    self.playerNode = playerNode
    activeCallId = callId
    // Route changes (Bluetooth, headphones) stop the engine; rebuild it.
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self, weak engine] _ in
      guard let self, let engine, self.engine === engine, let callId = self.activeCallId else {
        return
      }
      self.stop()
      self.start(callId: callId)
    }
  }

  func stop(callId: String) {
    guard activeCallId == callId else {
      return
    }
    stop()
  }

  func stop() {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    playerNode?.stop()
    engine?.stop()
    playerNode = nil
    engine = nil
    activeCallId = nil
  }

  private static func makeCycleBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameCount = AVAudioFrameCount(sampleRate * cycleSeconds)
    guard
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
      let samples = buffer.floatChannelData?[0]
    else {
      return nil
    }
    buffer.frameLength = frameCount

    let toneFrames = Int(sampleRate * toneSeconds)
    let fadeFrames = Double(sampleRate * fadeSeconds)
    for frame in 0..<Int(frameCount) {
      guard frame < toneFrames else {
        samples[frame] = 0
        continue
      }
      let time = Double(frame) / sampleRate
      // Short linear fade at both edges to avoid clicks.
      let envelope = min(1, Double(frame) / fadeFrames, Double(toneFrames - frame) / fadeFrames)
      let value = toneFrequencies.reduce(0) { $0 + sin(2 * .pi * $1 * time) }
      samples[frame] = amplitude * Float(value * envelope)
    }
    return buffer
  }
}
