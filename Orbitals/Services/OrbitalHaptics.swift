import CoreHaptics
import UIKit

/// Short, causal feedback. Nothing runs continuously with the simulation clock.
@MainActor
final class OrbitalHaptics {
  static let shared = OrbitalHaptics()

  var enabled = true {
    didSet { if !enabled { stop() } }
  }
  var strength = 0.85

  private let selectionGenerator = UISelectionFeedbackGenerator()
  private let impactGenerator = UIImpactFeedbackGenerator(style: .rigid)
  private let notificationGenerator = UINotificationFeedbackGenerator()
  private let supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
  private var engine: CHHapticEngine?
  private var players: [Pulse: any CHHapticPatternPlayer] = [:]
  private var engineRunning = false
  private var lastFeedbackTime: TimeInterval = -.infinity
  private var lastDetent: Int?
  private var backgroundObserver: NSObjectProtocol?

  private enum Pulse: Hashable {
    case touch, detent, release, boundary

    var intensity: Float {
      switch self {
      case .touch: 0.64
      case .detent: 0.43
      case .release: 0.34
      case .boundary: 0.95
      }
    }

    var sharpness: Float {
      switch self {
      case .touch: 0.5
      case .detent: 0.86
      case .release: 0.38
      case .boundary: 0.64
      }
    }
  }

  private init() {
    // This singleton owns one observer for its lifetime. No idle polling/timers.
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.stop() }
    }
  }

  private var canPlay: Bool {
    enabled && strength.isFinite && strength > 0 && UIApplication.shared.applicationState == .active
  }

  private var intensity: Float { Float(min(1, max(0, strength))) }

  private func admit(interval: TimeInterval) -> Bool {
    guard canPlay else { return false }
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastFeedbackTime >= interval else { return false }
    lastFeedbackTime = now
    return true
  }

  func tap() {
    guard admit(interval: 0.028) else { return }
    play(.touch)
  }

  func selection() {
    guard admit(interval: 0.035) else { return }
    // Preserve the familiar semantic meaning of a system selection haptic.
    selectionGenerator.selectionChanged()
    selectionGenerator.prepare()
  }

  func beginAdjustment() {
    lastDetent = nil
    guard canPlay else { return }
    impactGenerator.prepare()
    selectionGenerator.prepare()
    guard admit(interval: 0.035) else { return }
    play(.touch)
  }

  func detent(normalized: Double) {
    guard normalized.isFinite, canPlay else { return }
    let position = min(1, max(0, normalized))
    let detent = Int((position * 72).rounded())
    guard detent != lastDetent else { return }
    lastDetent = detent
    // Coalesce rapid dragging instead of queuing a vibration for every frame.
    guard admit(interval: 0.045) else { return }
    play(detent == 0 || detent == 72 ? .boundary : .detent)
  }

  func endAdjustment() {
    lastDetent = nil
    guard admit(interval: 0.035) else { return }
    play(.release)
  }

  func boundary() {
    guard admit(interval: 0.09) else { return }
    play(.boundary)
  }

  func success() {
    guard admit(interval: 0.06) else { return }
    notificationGenerator.notificationOccurred(.success)
  }

  func stop() {
    players.values.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
    engine?.stop(completionHandler: nil)
    engineRunning = false
    lastDetent = nil
    lastFeedbackTime = -.infinity
  }

  private func prepareEngine() throws -> CHHapticEngine {
    let current: CHHapticEngine
    if let engine {
      current = engine
    } else {
      current = try CHHapticEngine()
      current.playsHapticsOnly = true
      current.isAutoShutdownEnabled = true
      current.stoppedHandler = { [weak self] _ in
        Task { @MainActor [weak self] in self?.engineRunning = false }
      }
      current.resetHandler = { [weak self] in
        Task { @MainActor [weak self] in
          // Recreate players lazily on the next deliberate interaction.
          self?.players.removeAll()
          self?.engineRunning = false
        }
      }
      engine = current
    }
    if !engineRunning {
      try current.start()
      engineRunning = true
    }
    return current
  }

  private func play(_ pulse: Pulse) {
    if supportsCoreHaptics {
      do {
        let engine = try prepareEngine()
        let player: any CHHapticPatternPlayer
        if let cached = players[pulse] {
          player = cached
        } else {
          let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
              CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness),
            ],
            relativeTime: 0
          )
          let pattern = try CHHapticPattern(events: [event], parameters: [])
          player = try engine.makePlayer(with: pattern)
          players[pulse] = player
        }
        try player.sendParameters(
          [
            CHHapticDynamicParameter(
              parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
          ], atTime: CHHapticTimeImmediate)
        try player.start(atTime: CHHapticTimeImmediate)
        return
      } catch {
        // Hardware interruptions and unsupported destinations remain usable.
        players.removeAll()
        engineRunning = false
      }
    }
    impactGenerator.impactOccurred(intensity: CGFloat(intensity * pulse.intensity))
    impactGenerator.prepare()
  }
}
