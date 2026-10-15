import XCTest

@testable import Orbitals

@MainActor
final class ModelTests: XCTestCase {
  private func makeModel() -> OrbitModel {
    // This is the test app's defaults domain. Every test starts independently of restoration.
    UserDefaults.standard.removeObject(forKey: "Orbitals.experiment.v1")
    let model = OrbitModel()
    model.reset()
    model.running = false
    return model
  }

  private func advance(_ model: OrbitModel, ticks: Int) {
    for _ in 0..<ticks { model.step() }
  }

  func testPauseAndSingleStepUseExactSimulationTick() {
    let model = makeModel()
    model.advanceFrame(timestamp: 10)
    model.advanceFrame(timestamp: 11)
    XCTAssertEqual(model.renderSnapshot().time, 0)
    model.step()
    XCTAssertFalse(model.running)
    XCTAssertEqual(model.renderSnapshot().time, 1.0 / 60, accuracy: 1e-12)
    XCTAssertEqual(model.displayTime, 1.0 / 60, accuracy: 1e-12)
    XCTAssertEqual(model.renderSnapshot().samples.count, 2)
    model.step()
    XCTAssertEqual(model.renderSnapshot().time, 2.0 / 60, accuracy: 1e-12)
    XCTAssertEqual(model.points, OrbitalMath.pointsAt(2.0 / 60, settings: model.settings))
  }

  func testControlEditsKeepClockAndArchivedSamples() {
    let model = makeModel()
    advance(model, ticks: 80)
    let original = model.renderSnapshot()
    model.setChannel(\.frequency, 0.83)
    model.setChannel(\.speed, 2.7)
    model.setChannel(\.amplitude, 0.91)
    model.setChannel(\.phase, 56)
    model.setChannel(\.motion, .lissajous)
    model.settings.radius = 1.1
    model.settings.glow = 0.3
    model.settings.persistence = 7
    model.setDimension(5)
    model.horizon = 12
    model.plane = .zw
    model.inspectionOffset = -0.5
    model.retconPhase = 55
    model.ghostStrength = 0.7
    model.setCamera(yaw: 42, pitch: 18)
    XCTAssertEqual(model.renderSnapshot().time, original.time)
    XCTAssertEqual(model.renderSnapshot().samples, original.samples)
    XCTAssertEqual(model.points, OrbitalMath.pointsAt(original.time, settings: model.settings))
    XCTAssertNotEqual(model.points, original.samples.last!.points)
    model.step()
    XCTAssertEqual(
      Array(model.renderSnapshot().samples.prefix(original.samples.count)), original.samples)
    XCTAssertEqual(TimelineMath.splitSegments(model.renderSnapshot().samples).count, 2)
  }

  func testChannelLinkingAndIndependentEdits() {
    let model = makeModel()
    let initial = model.settings.channels
    model.selectedChannel = 1
    model.setChannel(\.amplitude, 0.3)
    XCTAssertEqual(model.settings.channels[0], initial[0])
    XCTAssertEqual(model.settings.channels[2], initial[2])
    XCTAssertEqual(model.settings.channels[1].amplitude, 0.3)
    model.linked = true
    XCTAssertEqual(model.settings.channels[0], model.settings.channels[1])
    XCTAssertEqual(model.settings.channels[1], model.settings.channels[2])
    model.setChannel(\.motion, .precession)
    XCTAssertTrue(model.settings.channels.allSatisfy { $0.motion == .precession })
    model.linked = false
    model.setChannel(\.speed, 2)
    XCTAssertEqual(model.settings.channels.map(\.speed), [1, 2, 1])
  }

  func testRetconPhaseChangesPastAndFutureWithOriginalEvidenceIntact() {
    let model = makeModel()
    model.chooseView(.retcon)
    advance(model, ticks: 150)
    let archive = model.renderSnapshot().samples
    model.retconOffset = -0.75
    let beforePast = model.retconRewritten
    let originalPast = model.retconOriginal
    XCTAssertNotNil(originalPast)
    model.retconOffset = 0.75
    let beforeFuture = model.retconRewritten
    XCTAssertNil(model.retconOriginal)
    let revision = model.retconRevision
    model.retconPhase += 35
    let afterFuture = model.retconRewritten
    XCTAssertNotEqual(beforeFuture, afterFuture)
    XCTAssertEqual(model.retconRevision, revision + 1)
    model.retconOffset = -0.75
    XCTAssertNotEqual(model.retconRewritten, beforePast)
    XCTAssertEqual(model.retconOriginal, originalPast)
    XCTAssertEqual(model.renderSnapshot().samples, archive)
    XCTAssertNotNil(model.retconDeltas)
    XCTAssertTrue(model.retconDeltas!.allSatisfy { $0 >= 0 })
  }

  func testRetconPresentShowsActualRecordedSnapshot() {
    let model = makeModel()
    model.chooseView(.retcon)
    advance(model, ticks: 20)
    model.retconOffset = 0
    XCTAssertEqual(model.retconOriginal, model.renderSnapshot().samples.last!.points)
    XCTAssertEqual(model.retconTime, model.renderSnapshot().samples.last!.t)
    let revision = model.retconRevision
    model.setCamera(yaw: -75, pitch: 60)
    model.settings.glow = 0.2
    XCTAssertEqual(model.retconRevision, revision)
  }

  func testLoopOnlyChangesTrackProgramAndNotGlobalModelOrHistory() {
    let model = makeModel()
    model.chooseView(.tracks)
    advance(model, ticks: 90)
    let settings = model.settings
    let original = model.renderSnapshot()
    model.loopEnabled = true
    model.applyLoopPreset("Resonance sweep")
    model.loopProgram.depth = 0.9
    model.loopProgram.pace = 4
    model.loopProgram.excitation = 5
    XCTAssertEqual(model.settings, settings)
    XCTAssertEqual(model.renderSnapshot().time, original.time)
    XCTAssertEqual(model.renderSnapshot().samples, original.samples)
    XCTAssertEqual(model.renderSnapshot().loopEpoch, original.time)
    for index in 0..<3 {
      XCTAssertEqual(
        model.renderSnapshot().loopOrigins[index],
        TrackMath.naturalPhase(original.time, index: index, settings: settings), accuracy: 1e-12)
    }
    model.chooseView(.cylinder)
    XCTAssertEqual(model.renderSnapshot().settings, settings)
    XCTAssertEqual(model.points, OrbitalMath.pointsAt(original.time, settings: settings))
    XCTAssertEqual(model.renderSnapshot().samples, original.samples)
  }

  func testClearTrailsKeepsHistoryAndClock() {
    let model = makeModel()
    advance(model, ticks: 80)
    let original = model.renderSnapshot()
    model.clearTrails()
    let cleared = model.renderSnapshot()
    XCTAssertEqual(cleared.time, original.time)
    XCTAssertEqual(cleared.samples, original.samples)
    XCTAssertEqual(cleared.trailCutoff, original.time)
  }

  func testClearHistoryKeepsClockAndCurrentCoordinateSnapshot() {
    let model = makeModel()
    model.chooseView(.retcon)
    advance(model, ticks: 120)
    let time = model.renderSnapshot().time
    model.retconOffset = -0.5
    XCTAssertNotNil(model.retconOriginal)
    model.clearHistory()
    let snapshot = model.renderSnapshot()
    XCTAssertEqual(snapshot.time, time)
    XCTAssertEqual(snapshot.samples.count, 1)
    XCTAssertEqual(snapshot.samples[0].t, time)
    XCTAssertEqual(snapshot.samples[0].points, OrbitalMath.pointsAt(time, settings: model.settings))
    XCTAssertNil(model.retconOriginal)
    XCTAssertEqual(model.archiveSeconds, 0)
    XCTAssertEqual(model.retconRevision, 1)
  }

  func testResetRestoresExperimentAndClearsLoopAndCameras() {
    let model = makeModel()
    model.chooseView(.retcon)
    advance(model, ticks: 70)
    model.setCamera(yaw: 72, pitch: -60)
    model.linked = true
    model.settings.radius = 0.6
    model.loopEnabled = true
    model.applyLoopPreset("Slow drift")
    model.retconPhase = -145
    model.reset()
    model.running = false
    XCTAssertEqual(model.renderSnapshot().time, 0)
    XCTAssertEqual(model.settings, OrbitalSettings())
    XCTAssertEqual(model.dimension, 2)
    XCTAssertEqual(model.selectedView, .spatial)
    XCTAssertEqual(model.camera, ViewCamera(yaw: 0, pitch: 0))
    XCTAssertFalse(model.linked)
    XCTAssertFalse(model.loopEnabled)
    XCTAssertEqual(model.loopProgram, LoopProgram())
    XCTAssertEqual(model.retconPhase, 30)
    XCTAssertEqual(model.retconRevision, 1)
    XCTAssertEqual(model.renderSnapshot().samples.count, 1)
    XCTAssertEqual(model.renderSnapshot().samples.first!.t, 0)
    model.chooseView(.retcon)
    XCTAssertEqual(model.camera, ViewCamera(yaw: 0, pitch: 38))
  }

  func testAllFiveViewsSelectAndTemporalViewsEnableFifthDimension() {
    let model = makeModel()
    XCTAssertEqual(OrbitalViewKind.allCases.count, 5)
    for view in OrbitalViewKind.allCases {
      model.setDimension(2)
      model.chooseView(view)
      XCTAssertEqual(model.selectedView, view)
      XCTAssertEqual(model.renderSnapshot().kind, view)
      if view == .spatial {
        XCTAssertEqual(model.dimension, 2)
      } else {
        XCTAssertEqual(model.dimension, 5)
        XCTAssertTrue(model.settings.fourD)
        XCTAssertEqual(model.settings.morph, 1)
      }
    }
    model.setDimension(3)
    XCTAssertEqual(model.selectedView, .spatial)
    XCTAssertFalse(model.settings.fourD)
    XCTAssertEqual(model.settings.morph, 1)
  }

  func testEveryCameraRotatesResetsAndRestoresIndependently() {
    let model = makeModel()
    let expectedPitch: [OrbitalViewKind: Double] = [
      .spatial: 0, .cylinder: 10, .torus: 35, .tracks: 40, .retcon: 38,
    ]
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      model.setCamera(yaw: 450, pitch: -120)
      XCTAssertEqual(model.camera, ViewCamera(yaw: 90, pitch: -85))
      XCTAssertEqual(model.renderSnapshot().camera, model.camera)
      model.resetCamera()
      XCTAssertEqual(model.camera.pitch, expectedPitch[view]!)
      XCTAssertEqual(model.camera.yaw, view == .cylinder ? 16 : 0)
    }
    model.chooseView(.torus)
    model.setCamera(yaw: -77, pitch: 25)
    model.chooseView(.retcon)
    model.setCamera(yaw: 41, pitch: -31)
    model.chooseView(.torus)
    XCTAssertEqual(model.camera, ViewCamera(yaw: -77, pitch: 25))
    model.chooseView(.retcon)
    XCTAssertEqual(model.camera, ViewCamera(yaw: 41, pitch: -31))
  }

  func testBackgroundSuspensionDoesNotAdvanceOrCatchUpClock() {
    let model = makeModel()
    model.running = true
    model.advanceFrame(timestamp: 10)
    model.advanceFrame(timestamp: 10.05)
    XCTAssertEqual(model.renderSnapshot().time, 0.05, accuracy: 1e-12)
    model.setActive(false)
    let beforeBackground = model.renderSnapshot()
    model.advanceFrame(timestamp: 100)
    model.advanceFrame(timestamp: 200)
    XCTAssertEqual(model.renderSnapshot().time, beforeBackground.time)
    XCTAssertEqual(model.renderSnapshot().samples, beforeBackground.samples)
    model.setActive(true)
    model.advanceFrame(timestamp: 300)
    XCTAssertEqual(model.renderSnapshot().time, beforeBackground.time)
    model.advanceFrame(timestamp: 300.025)
    XCTAssertEqual(model.renderSnapshot().time, beforeBackground.time + 0.025, accuracy: 1e-12)
  }

  func testPauseResumeDropsWallClockGapAndLongFrameIsBounded() {
    let model = makeModel()
    model.running = true
    model.advanceFrame(timestamp: 1)
    model.advanceFrame(timestamp: 1.05)
    model.running = false
    let paused = model.renderSnapshot().time
    model.advanceFrame(timestamp: 200)
    model.running = true
    model.advanceFrame(timestamp: 300)
    XCTAssertEqual(model.renderSnapshot().time, paused)
    model.advanceFrame(timestamp: 310)
    XCTAssertEqual(model.renderSnapshot().time, paused + 0.1, accuracy: 1e-12)
  }
}
