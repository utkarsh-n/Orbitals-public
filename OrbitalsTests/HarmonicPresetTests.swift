import XCTest

@testable import Orbitals

@MainActor
final class HarmonicPresetTests: XCTestCase {
  private func makeModel() -> OrbitModel {
    UserDefaults.standard.removeObject(forKey: "Orbitals.experiment.v1")
    let model = OrbitModel()
    model.reset()
    model.running = false
    return model
  }

  private func settings(for preset: HarmonicPreset, fourD: Bool = false) -> OrbitalSettings {
    var settings = OrbitalSettings()
    settings.channels = preset.channels
    settings.morph = 1
    settings.fourD = fourD
    settings.xw = 31
    settings.yw = -24
    settings.zw = 18
    return settings
  }

  func testUnisonAndCounterphaseMaintainTheirRelationsInEveryDimension() {
    for fourD in [false, true] {
      let unison = settings(for: .unison, fourD: fourD)
      let counterphase = settings(for: .counterphase, fourD: fourD)
      for t in [0.0, 0.37, 2.6, 11.2] {
        let together = OrbitalMath.pointsAt(t, settings: unison)
        XCTAssertEqual(together[0], together[1])
        XCTAssertEqual(together[1], together[2])
        let opposite = OrbitalMath.pointsAt(t, settings: counterphase)
        XCTAssertEqual(OrbitalMath.norm(opposite[0] + opposite[1]), 0, accuracy: 1e-10)
        XCTAssertEqual(opposite[0], opposite[2])
      }
    }
  }

  func testThreePhaseMaintainsBalancedTriangleAfterFourDimensionalRotation() {
    let s = settings(for: .threePhase, fourD: true)
    for t in [0.0, 1.25, 9.7] {
      let p = OrbitalMath.pointsAt(t, settings: s)
      XCTAssertEqual(OrbitalMath.norm(p[0] + p[1] + p[2]), 0, accuracy: 1e-10)
      for index in 0..<3 {
        XCTAssertEqual(OrbitalMath.norm(p[index]), s.radius, accuracy: 1e-10)
        XCTAssertEqual(
          OrbitalMath.distance(p[index], p[(index + 1) % 3]),
          sqrt(3) * s.radius, accuracy: 1e-10)
      }
    }
  }

  func testLaplaceRatesAndResonantAngleRemainLockedAndRepeat() {
    let s = settings(for: .laplace, fourD: true)
    let rates = s.channels.map { $0.speed * $0.frequency }
    XCTAssertEqual(rates[0] / rates[2], 4, accuracy: 1e-12)
    XCTAssertEqual(rates[1] / rates[2], 2, accuracy: 1e-12)
    for t in [0.0, 0.23, 4.8, 17.0] {
      let longitude = s.channels.map { 360 * $0.speed * $0.frequency * t + $0.phase }
      XCTAssertEqual(longitude[0] - 3 * longitude[1] + 2 * longitude[2], 180, accuracy: 1e-10)
      for index in 0..<3 {
        XCTAssertEqual(
          OrbitalMath.distance(
            OrbitalMath.pointAt(t, index: index, settings: s),
            OrbitalMath.pointAt(t + 10, index: index, settings: s)),
          0, accuracy: 1e-10)
      }
    }
  }

  func testBeatAlignmentOccursAtExpectedRelativePeriods() {
    let s = settings(for: .beats)
    let halfCycle = OrbitalMath.pointsAt(50, settings: s)
    XCTAssertEqual(OrbitalMath.distance(halfCycle[0], halfCycle[1]), 2 * s.radius, accuracy: 1e-10)
    XCTAssertEqual(OrbitalMath.distance(halfCycle[0], halfCycle[2]), 0, accuracy: 1e-10)
    let fullCycle = OrbitalMath.pointsAt(100, settings: s)
    XCTAssertEqual(OrbitalMath.distance(fullCycle[0], fullCycle[1]), 0, accuracy: 1e-10)
    XCTAssertEqual(OrbitalMath.distance(fullCycle[0], fullCycle[2]), 0, accuracy: 1e-10)
  }

  func testLissajousHarmonicsHaveClosedBoundedPathsInFourDimensions() {
    let s = settings(for: .lissajous, fourD: true)
    for index in 0..<3 {
      for tick in 0...200 {
        let time = Double(tick) / 20
        let point = OrbitalMath.pointAt(time, index: index, settings: s)
        XCTAssertLessThanOrEqual(OrbitalMath.norm(point), s.radius * 0.85 + 1e-10)
        XCTAssertEqual(
          OrbitalMath.distance(point, OrbitalMath.pointAt(time + 10, index: index, settings: s)),
          0, accuracy: 1e-10)
      }
    }
  }

  func testApplyingHarmonicStartsReproducibleRecordingAndPreservesPresentation() {
    let model = makeModel()
    model.chooseView(.retcon)
    model.setCamera(yaw: 71, pitch: -18)
    model.setViewport(zoom: 2, panX: 0.2, panY: -0.3)
    model.settings.radius = 1.7
    model.settings.glow = 0.2
    model.selectedChannel = 2
    model.linked = true
    model.loopEnabled = true
    for _ in 0..<90 { model.step() }
    model.inspectionOffset = -0.5
    let previous = model.renderSnapshot()
    for preset in HarmonicPreset.allCases {
      model.applyHarmonic(preset)
      let next = model.renderSnapshot()
      XCTAssertEqual(next.time, 0)
      XCTAssertEqual(next.samples.count, 1)
      XCTAssertEqual(next.samples[0].t, 0)
      XCTAssertEqual(next.samples[0].points, OrbitalMath.pointsAt(0, settings: next.settings))
      XCTAssertEqual(next.settings.channels, preset.channels)
      XCTAssertEqual(next.settings.radius, previous.settings.radius)
      XCTAssertEqual(next.settings.glow, previous.settings.glow)
      XCTAssertEqual(next.settings.fourD, previous.settings.fourD)
      XCTAssertEqual(next.settings.morph, previous.settings.morph)
      XCTAssertEqual(next.camera, previous.camera)
      XCTAssertEqual(next.kind, previous.kind)
      XCTAssertEqual(model.dimension, 5)
      XCTAssertEqual(model.selectedChannel, 2)
      XCTAssertFalse(model.running)
      XCTAssertFalse(model.linked)
      XCTAssertFalse(model.loopEnabled)
      XCTAssertEqual(next.loopEpoch, 0)
      XCTAssertEqual(next.loopOrigins, [0, 0, 0])
      XCTAssertEqual(next.trailCutoff, 0)
      XCTAssertEqual(model.archiveSeconds, 0)
      XCTAssertEqual(model.inspectionOffset, 0)
      XCTAssertEqual(model.currentHarmonic, preset)
      for _ in 0..<20 { model.step() }
    }
  }

  func testDialResetIsScopedAndPreservesRecording() {
    let model = makeModel()
    model.applyHarmonic(.lissajous)
    model.selectedChannel = 1
    for _ in 0..<20 { model.step() }
    let before = model.renderSnapshot()
    model.resetMotionControls()
    XCTAssertEqual(model.settings.channels[0], before.settings.channels[0])
    XCTAssertEqual(model.settings.channels[2], before.settings.channels[2])
    XCTAssertEqual(model.settings.channels[1], OrbitalSettings().channels[1])
    XCTAssertEqual(model.renderSnapshot().time, before.time)
    XCTAssertEqual(model.renderSnapshot().samples, before.samples)
    model.linked = true
    model.setChannel(\.speed, 3)
    model.setChannel(\.phase, 50)
    model.resetMotionControls()
    XCTAssertTrue(model.settings.channels.allSatisfy { $0 == OrbitalSettings().channels[1] })
    XCTAssertTrue(model.linked)
    XCTAssertEqual(model.renderSnapshot().time, before.time)
    XCTAssertEqual(model.renderSnapshot().samples, before.samples)
  }

  func testPhaseAlignmentChangesOnlyPhasesAndPreservesHistory() {
    let model = makeModel()
    model.applyHarmonic(.lissajous)
    model.selectedChannel = 1
    model.setChannel(\.speed, 2)
    for _ in 0..<20 { model.step() }
    let before = model.renderSnapshot()
    var expected = before.settings
    for index in expected.channels.indices { expected.channels[index].phase = 0 }
    model.alignPhases()
    XCTAssertEqual(model.settings, expected)
    XCTAssertEqual(model.renderSnapshot().time, before.time)
    XCTAssertEqual(model.renderSnapshot().samples, before.samples)
    XCTAssertEqual(model.selectedChannel, 1)
    XCTAssertFalse(model.linked)
  }

  func testAlignmentResetsEveryViewWithoutChangingPhysicsOrPreset() {
    let model = makeModel()
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      model.setCamera(yaw: 53, pitch: -12)
      model.setViewport(zoom: 3, panX: 0.4, panY: -0.6)
    }
    model.applyHarmonic(.threePhase)
    for _ in 0..<20 { model.step() }
    let before = model.renderSnapshot()
    let revision = model.retconRevision
    model.alignAllViews()
    XCTAssertEqual(MotionSignature(model.settings), MotionSignature(before.settings))
    XCTAssertEqual(model.currentHarmonic, .threePhase)
    XCTAssertEqual(model.preset, HarmonicPreset.threePhase.title)
    XCTAssertEqual(model.renderSnapshot().time, before.time)
    XCTAssertEqual(model.renderSnapshot().samples, before.samples)
    XCTAssertEqual(model.selectedView, .retcon)
    XCTAssertEqual(model.retconRevision, revision)
    let expectedPitch: [OrbitalViewKind: Double] = [
      .spatial: 0, .cylinder: 10, .torus: 35, .tracks: 40, .retcon: 38,
    ]
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      XCTAssertEqual(
        model.camera, ViewCamera(yaw: view == .cylinder ? 16 : 0, pitch: expectedPitch[view]!))
    }
    model.setChannel(\.frequency, 0.5)
    XCTAssertNil(model.currentHarmonic)
  }
}
