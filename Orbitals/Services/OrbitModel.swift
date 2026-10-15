import Foundation
import Observation
import QuartzCore

enum CoordinatePlane: String, CaseIterable, Identifiable {
  case xy = "XY"
  case xz = "XZ"
  case xw = "XW"
  case yz = "YZ"
  case yw = "YW"
  case zw = "ZW"
  var id: String { rawValue }
  var indices: SIMD2<Int> {
    switch self {
    case .xy: [0, 1]
    case .xz: [0, 2]
    case .xw: [0, 3]
    case .yz: [1, 2]
    case .yw: [1, 3]
    case .zw: [2, 3]
    }
  }
}

@Observable @MainActor
final class OrbitModel: OrbitalSceneSource {
  var settings = OrbitalSettings() {
    didSet {
      // Historical points may exceed the new 4D eye plane when shrinking R.
      // Clear only optical trails; the immutable time archive remains intact.
      if settings.radius < oldValue.radius { trailCutoff = time }
      controlsChanged()
    }
  }
  var dimension = 2
  var selectedView: OrbitalViewKind = .spatial {
    didSet {
      invalidate()
      scheduleSave()
    }
  }
  var selectedChannel = 0
  var linked = false {
    didSet {
      if linked { linkChannels() }
      scheduleSave()
    }
  }
  var running = true {
    didSet {
      lastTimestamp = nil
      refreshReadouts()
      invalidate()
    }
  }
  var active = true
  var horizon = 8.0 {
    didSet {
      inspectionOffset = min(horizon, max(-horizon, inspectionOffset))
      retconOffset = min(horizon, max(-horizon, retconOffset))
      invalidate()
    }
  }
  var plane: CoordinatePlane = .xy { didSet { invalidate() } }
  var inspectionOffset = 0.0 {
    didSet {
      refreshReadouts()
      invalidate()
    }
  }
  var retconOffset = -2.0 {
    didSet {
      refreshReadouts()
      invalidate()
    }
  }
  var retconPhase = 30.0 {
    didSet {
      reviseRetcon()
      invalidate()
    }
  }
  var ghostStrength = 0.4 { didSet { invalidate() } }
  var loopEnabled = false {
    didSet {
      restartLoop()
      invalidate()
    }
  }
  var loopProgram = LoopProgram() {
    didSet {
      invalidate()
      scheduleSave()
    }
  }
  var loopPreset = "Orbital cadence"
  var preset = "Custom experiment"
  var hapticsEnabled = true {
    didSet {
      OrbitalHaptics.shared.enabled = hapticsEnabled
      scheduleSave()
    }
  }
  var hapticStrength = 0.85 {
    didSet {
      OrbitalHaptics.shared.strength = hapticStrength
      scheduleSave()
    }
  }
  var redrawKey = 0
  var displayTime = 0.0
  var points: [Vec4] = []
  var archiveSeconds = 0.0
  var inspectedPoints: [Vec4]?
  var inspectedTime = 0.0
  var retconOriginal: [Vec4]?
  var retconRewritten: [Vec4] = []
  var retconDeltas: [Double]?
  var retconTime = 0.0
  var retconRevision = 1
  var loopProgress = 0.0
  var camera = ViewCamera(yaw: 0, pitch: 0)
  var renderError: String?

  @ObservationIgnored private var recorder = TimelineRecorder()
  @ObservationIgnored private var time = 0.0
  @ObservationIgnored private var lastTimestamp: Double?
  @ObservationIgnored private var lastReport = -1.0
  @ObservationIgnored private var trailCutoff = 0.0
  @ObservationIgnored private var cameras: [String: ViewCamera] = [:]
  @ObservationIgnored private var loopEpoch = 0.0
  @ObservationIgnored private var loopOrigins = [0.0, 0.0, 0.0]
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var ready = false

  init() {
    if let data = UserDefaults.standard.data(forKey: "Orbitals.experiment.v1"),
      let saved = try? JSONDecoder().decode(SavedExperiment.self, from: data)
    {
      settings = saved.settings
      dimension = saved.dimension
      selectedView = OrbitalViewKind(rawValue: saved.view) ?? .spatial
      loopProgram = saved.loop
      hapticsEnabled = saved.haptics
      hapticStrength = saved.strength
    }
    if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
      settings = OrbitalSettings()
      dimension = 2
      selectedView = .spatial
      running = false
    }
    camera = defaultCamera(for: selectedView)
    OrbitalHaptics.shared.enabled = hapticsEnabled
    OrbitalHaptics.shared.strength = hapticStrength
    recorder.record(at: 0, settings: settings)
    ready = true
    lastRetconSettings = RetconMath.settings(base: settings, phaseShift: retconPhase)
    refreshReadouts()
  }

  var isAnimating: Bool { running && active }
  var clock: String {
    String(
      format: "%02d:%02d.%02d", Int(displayTime) / 60, Int(displayTime) % 60,
      Int(displayTime * 100) % 100)
  }

  func advanceFrame(timestamp: Double) {
    guard isAnimating else {
      lastTimestamp = nil
      return
    }
    defer { lastTimestamp = timestamp }
    guard let lastTimestamp else { return }
    time += min(max(timestamp - lastTimestamp, 0), 0.1)
    recorder.record(at: time, settings: settings)
    if time - lastReport >= 0.1 {
      refreshReadouts()
      lastReport = time
    }
  }

  func renderSnapshot() -> RenderSnapshot {
    RenderSnapshot(
      settings: settings, time: time, samples: recorder.samples, kind: selectedView, camera: camera,
      horizon: horizon, inspectionOffset: selectedView == .retcon ? retconOffset : inspectionOffset,
      planeIndices: plane.indices, loopEnabled: loopEnabled, loopProgram: loopProgram,
      loopEpoch: loopEpoch, loopOrigins: loopOrigins, retconPhase: retconPhase,
      ghostStrength: ghostStrength, trailCutoff: trailCutoff)
  }

  func setActive(_ value: Bool) {
    active = value
    lastTimestamp = nil
    invalidate()
  }
  func invalidate() { redrawKey &+= 1 }
  func step() {
    running = false
    time += 1 / 60
    recorder.record(at: time, settings: settings)
    refreshReadouts()
    invalidate()
  }
  func clearTrails() {
    trailCutoff = time
    invalidate()
  }
  func clearHistory() {
    recorder.clear()
    recorder.record(at: time, settings: settings)
    retconRevision = 1
    refreshReadouts()
    invalidate()
  }
  func reset() {
    time = 0
    lastTimestamp = nil
    lastReport = -1
    trailCutoff = 0
    recorder.clear()
    loopEpoch = 0
    loopOrigins = [0, 0, 0]
    loopEnabled = false
    loopProgram = LoopProgram()
    loopPreset = "Orbital cadence"
    linked = false
    selectedChannel = 0
    settings = OrbitalSettings()
    dimension = 2
    selectedView = .spatial
    cameras.removeAll()
    camera = defaultCamera(for: .spatial)
    retconPhase = 30
    retconRevision = 1
    retconOffset = -2
    inspectionOffset = 0
    preset = "Custom experiment"
    running = true
    refreshReadouts()
    invalidate()
    save()
  }
  func setDimension(_ value: Int) {
    dimension = value
    var s = settings
    s.fourD = value >= 4
    s.morph = value == 2 ? 0 : 1
    settings = s
    if value < 5 && selectedView != .spatial { chooseView(.spatial) }
    invalidate()
    scheduleSave()
  }
  func chooseView(_ view: OrbitalViewKind) {
    cameras[selectedView.rawValue] = camera
    if view != .spatial && dimension != 5 { setDimension(5) }
    selectedView = view
    camera = cameras[view.rawValue] ?? defaultCamera(for: view)
    refreshReadouts()
    invalidate()
  }
  func setCamera(yaw: Double, pitch: Double) {
    guard yaw.isFinite, pitch.isFinite else { return }
    var next = camera
    let wrappedYaw = yaw.truncatingRemainder(dividingBy: 360)
    next.yaw =
      wrappedYaw >= 180 ? wrappedYaw - 360 : wrappedYaw < -180 ? wrappedYaw + 360 : wrappedYaw
    next.pitch = min(85, max(-85, pitch))
    guard next != camera else { return }
    camera = next
    if selectedView == .spatial {
      var nextSettings = settings
      nextSettings.yaw = camera.yaw
      nextSettings.pitch = camera.pitch
      settings = nextSettings
    }
    cameras[selectedView.rawValue] = camera
    invalidate()
  }

  /// Zoom is relative to the fitted scene; pan is a fraction of viewport width/height.
  /// These are optical changes and never modify the clock, geometry, or recorded archive.
  func setViewport(zoom: Double? = nil, panX: Double? = nil, panY: Double? = nil) {
    guard zoom?.isFinite ?? true, panX?.isFinite ?? true, panY?.isFinite ?? true else { return }
    var next = camera
    if let zoom { next.zoom = min(6, max(0.25, zoom)) }
    if let panX { next.panX = min(1.5, max(-1.5, panX)) }
    if let panY { next.panY = min(1.5, max(-1.5, panY)) }
    guard next != camera else { return }
    camera = next
    cameras[selectedView.rawValue] = camera
    invalidate()
  }

  func panCamera(dx: Double, dy: Double) {
    guard dx.isFinite, dy.isFinite else { return }
    // Bound the input before adding, so even a very large finite delta cannot overflow.
    let x = camera.panX + min(3, max(-3, dx))
    let y = camera.panY + min(3, max(-3, dy))
    setViewport(panX: x, panY: y)
  }

  /// The anchor is measured from the unpanned center at (0.5w, 0.48h).
  /// Applying the actual clamped ratio keeps the touched scene point under the fingers.
  func zoomCamera(by factor: Double, anchor: SIMD2<Double> = .zero) {
    guard factor.isFinite, factor > 0, anchor.x.isFinite, anchor.y.isFinite else { return }
    let zoom = min(6, max(0.25, camera.zoom * factor))
    let ratio = zoom / camera.zoom
    guard ratio != 1 else { return }
    let x = anchor.x - (anchor.x - camera.panX) * ratio
    let y = anchor.y - (anchor.y - camera.panY) * ratio
    setViewport(zoom: zoom, panX: min(1.5, max(-1.5, x)), panY: min(1.5, max(-1.5, y)))
  }

  func resetCamera() {
    let c =
      selectedView == .spatial ? ViewCamera(yaw: 0, pitch: 0) : defaultCamera(for: selectedView)
    setCamera(yaw: c.yaw, pitch: c.pitch)
    setViewport(zoom: 1, panX: 0, panY: 0)
  }

  /// Restore every view's fitted orientation without touching motion or recorded evidence.
  func alignAllViews() {
    let previousPreset = preset
    var next = settings
    next.yaw = 0
    next.pitch = 0
    settings = next
    cameras.removeAll()
    camera = defaultCamera(for: selectedView)
    preset = previousPreset
    invalidate()
  }

  private func defaultCamera(for view: OrbitalViewKind) -> ViewCamera {
    switch view {
    case .spatial: ViewCamera(yaw: settings.yaw, pitch: settings.pitch)
    case .cylinder: ViewCamera(yaw: 16, pitch: 10)
    case .torus: ViewCamera(yaw: 0, pitch: 35)
    case .tracks: ViewCamera(yaw: 0, pitch: 40)
    case .retcon: ViewCamera(yaw: 0, pitch: 38)
    }
  }
  func setChannel<Value>(_ key: WritableKeyPath<Channel, Value>, _ value: Value) {
    var s = settings
    for i in s.channels.indices where linked || i == selectedChannel {
      s.channels[i][keyPath: key] = value
    }
    settings = s
  }

  /// Restore the selected channel's original dials. Linked channels share that default.
  /// Like any dial edit, this preserves the clock and all previously recorded samples.
  func resetMotionControls() {
    guard settings.channels.indices.contains(selectedChannel) else { return }
    let defaults = OrbitalSettings().channels[selectedChannel]
    var next = settings
    for index in next.channels.indices where linked || index == selectedChannel {
      next.channels[index] = defaults
    }
    settings = next
  }

  /// Align the phase parameters, not necessarily the positions of unlike motion modes.
  func alignPhases() {
    var next = settings
    for index in next.channels.indices { next.channels[index].phase = 0 }
    settings = next
  }

  /// Matching the actual parameters keeps this identity stable across optical edits.
  var currentHarmonic: HarmonicPreset? {
    HarmonicPreset.allCases.first { $0.channels == settings.channels }
  }

  /// A harmonic starts a new recording at an exact epoch, so its phase relations are
  /// reproducible. Geometry, presentation, selected view and transport state stay intact.
  func applyHarmonic(_ harmonic: HarmonicPreset) {
    var next = settings
    next.channels = harmonic.channels
    time = 0
    lastTimestamp = nil
    lastReport = -1
    trailCutoff = 0
    recorder.clear()
    linked = false
    loopEnabled = false
    loopEpoch = 0
    loopOrigins = [0, 0, 0]
    settings = next
    retconRevision = 1
    inspectionOffset = 0
    preset = harmonic.title
    refreshReadouts()
    invalidate()
  }

  private func linkChannels() {
    var s = settings
    let selected = s.channels[selectedChannel]
    s.channels = s.channels.map { _ in selected }
    settings = s
  }
  func restartLoop() {
    loopEpoch = time
    loopOrigins = (0..<3).map { TrackMath.naturalPhase(time, index: $0, settings: settings) }
    refreshReadouts()
    invalidate()
  }
  func applyLoopPreset(_ name: String) {
    guard let program = LoopProgram.presets[name] else { return }
    loopPreset = name
    loopProgram = program
    restartLoop()
  }
  func applyPreset(_ name: String) {
    var next = OrbitalSettings()
    if name == "Spherical orbits" {
      next.morph = 1
      next.yaw = 28
      next.pitch = 20
    }
    if name == "Lissajous study" {
      next.morph = 1
      next.yaw = 25
      next.persistence = 6
      for i in next.channels.indices {
        next.channels[i].motion = .lissajous
        next.channels[i].amplitude = 1
      }
    }
    if name == "Hyperspace" {
      next.morph = 1
      next.fourD = true
      next.xw = 38
      next.yw = 28
      next.zw = 12
      next.yaw = 25
      for i in next.channels.indices { next.channels[i].motion = .precession }
    }
    time = 0
    recorder.clear()
    lastTimestamp = nil
    lastReport = -1
    trailCutoff = 0
    linked = false
    loopEnabled = false
    settings = next
    dimension = next.fourD ? 4 : next.morph > 0 ? 3 : 2
    // A new experiment starts with fitted views, rather than inheriting a prior scene's crop.
    cameras.removeAll()
    selectedView = .spatial
    camera = ViewCamera(yaw: next.yaw, pitch: next.pitch)
    retconRevision = 1
    preset = name
    refreshReadouts()
    invalidate()
  }
  private func controlsChanged() {
    guard ready else { return }
    preset = "Custom experiment"
    recorder.record(at: time, settings: settings)
    reviseRetcon()
    invalidate()
    scheduleSave()
  }
  @ObservationIgnored private var lastRetconSettings: OrbitalSettings?
  private func reviseRetcon() {
    let s = RetconMath.settings(base: settings, phaseShift: retconPhase)
    if let old = lastRetconSettings {
      if old.channels != s.channels || old.radius != s.radius || old.morph != s.morph
        || old.fourD != s.fourD || old.xw != s.xw || old.yw != s.yw || old.zw != s.zw
      {
        retconRevision += 1
      }
    }
    lastRetconSettings = s
    refreshReadouts()
  }
  func refreshReadouts() {
    displayTime = time
    points = OrbitalMath.pointsAt(time, settings: settings)
    archiveSeconds = max(0, time - (recorder.samples.first?.t ?? time))
    let actual =
      inspectionOffset < 0
      ? TimelineMath.recordedAt(recorder.samples, time: time + inspectionOffset) : nil
    inspectedTime = actual?.t ?? time + inspectionOffset
    inspectedPoints =
      inspectionOffset < 0
      ? actual?.points : OrbitalMath.pointsAt(inspectedTime, settings: settings)
    let original =
      retconOffset <= 0 ? TimelineMath.recordedAt(recorder.samples, time: time + retconOffset) : nil
    retconTime = original?.t ?? time + retconOffset
    retconOriginal = original?.points
    retconRewritten = OrbitalMath.pointsAt(
      retconTime, settings: RetconMath.settings(base: settings, phaseShift: retconPhase))
    retconDeltas = original.map { old in
      zip(old.points, retconRewritten).map { OrbitalMath.distance($0, $1) }
    }
    loopProgress = TrackMath.modulo((time - loopEpoch) / loopProgram.duration)
  }
  private func scheduleSave() {
    guard ready else { return }
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self?.save()
    }
  }
  func save() {
    let saved = SavedExperiment(
      settings: settings, dimension: dimension, view: selectedView.rawValue, loop: loopProgram,
      haptics: hapticsEnabled, strength: hapticStrength)
    if let data = try? JSONEncoder().encode(saved) {
      UserDefaults.standard.set(data, forKey: "Orbitals.experiment.v1")
    }
  }
}

private struct SavedExperiment: Codable {
  var settings: OrbitalSettings
  var dimension: Int
  var view: String
  var loop: LoopProgram
  var haptics: Bool
  var strength: Double
}
