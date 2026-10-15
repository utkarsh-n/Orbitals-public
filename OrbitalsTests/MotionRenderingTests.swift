import XCTest
import simd

@testable import Orbitals

@MainActor
final class MotionRenderingTests: XCTestCase {
  private let cyan = SIMD3<Float>(0.1, 0.93, 1)

  private func snapshot(_ settings: OrbitalSettings, kind: OrbitalViewKind, time: Double = 2.3)
    -> RenderSnapshot
  {
    RenderSnapshot(
      settings: settings, time: time, samples: [], kind: kind,
      camera: ViewCamera(yaw: 17, pitch: 31), horizon: 3, inspectionOffset: 0,
      planeIndices: [0, 1], loopEnabled: false, loopProgram: LoopProgram(), loopEpoch: 0,
      loopOrigins: [0, 0, 0], retconPhase: 30, ghostStrength: 0.4, trailCutoff: 0)
  }

  private func channelSegments(_ geometry: SceneGeometry, dashedOnly: Bool = false)
    -> [SIMD4<Float>]
  {
    geometry.segments.filter {
      // Gradient guides no longer carry one channel's solid RGB along their
      // whole path. Select their dashed geometry independently of paint.
      if dashedOnly { return $0.style.z == 6 }
      let startColor = SIMD3($0.color.x, $0.color.y, $0.color.z)
      let endColor = SIMD3($0.detail.y, $0.detail.z, $0.detail.w)
      return startColor == cyan || startColor != endColor
    }.map { SIMD4($0.start.x, $0.start.y, $0.end.x, $0.end.y) }
  }

  func testPhysicalCycleGuidesCloseAndAgreeWithTheMotionEquations() {
    for fourD in [false, true] {
      for motion in Motion.allCases {
        var settings = OrbitalSettings()
        settings.fourD = fourD
        settings.morph = 0.8
        settings.channels[0] = Channel(
          motion: motion, speed: 1.4, amplitude: 0.73, frequency: 0.37, phase: 57)
        let turns = TrackMath.periodTurns(motion: motion, fourD: fourD)
        XCTAssertLessThan(
          simd_distance(
            TrackMath.cyclePoint(fraction: 0, index: 0, settings: settings),
            TrackMath.cyclePoint(fraction: 1, index: 0, settings: settings)), 1e-9)
        for time in [-0.3, 0, 1.7, 8.2] {
          let fraction = time * settings.channels[0].frequency * settings.channels[0].speed / turns
          XCTAssertLessThan(
            simd_distance(
              TrackMath.cyclePoint(fraction: fraction, index: 0, settings: settings),
              OrbitalMath.pointAt(time, index: 0, settings: settings)), 1e-9)
        }
        var stopped = settings
        stopped.channels[0].speed = 0
        stopped.channels[0].frequency = 0.01
        XCTAssertEqual(TrackMath.trackShapeKey(settings), TrackMath.trackShapeKey(stopped))
        XCTAssertEqual(
          TrackMath.cyclePoint(fraction: 0.3, index: 0, settings: settings),
          TrackMath.cyclePoint(fraction: 0.3, index: 0, settings: stopped))
      }
    }
  }

  func testPausedSharedStartingPointStillShowsChangedMotionGuide() {
    var settings = OrbitalSettings()
    settings.axes = false
    settings.trails = false
    let orbitPoint = OrbitalMath.pointAt(0, index: 0, settings: settings)
    let geometry = SceneGeometry()
    geometry.update(
      snapshot(settings, kind: .spatial, time: 0), size: CGSize(width: 390, height: 340),
      capacity: 32_768)
    let orbitGuide = channelSegments(geometry, dashedOnly: true)
    XCTAssertEqual(orbitGuide.count, 3 * 320)

    settings.channels[0].motion = .pendulum
    XCTAssertEqual(OrbitalMath.pointAt(0, index: 0, settings: settings), orbitPoint)
    geometry.update(
      snapshot(settings, kind: .spatial, time: 0), size: CGSize(width: 390, height: 340),
      capacity: 32_768)
    XCTAssertNotEqual(channelSegments(geometry, dashedOnly: true), orbitGuide)

    settings.mesh = false
    geometry.update(
      snapshot(settings, kind: .spatial, time: 0), size: CGSize(width: 390, height: 340),
      capacity: 32_768)
    XCTAssertTrue(channelSegments(geometry, dashedOnly: true).isEmpty)
  }

  func testEveryRendererRespondsToMotionChangesWithoutAdvancingTheClock() {
    let geometry = SceneGeometry()
    for kind in OrbitalViewKind.allCases {
      var settings = OrbitalSettings()
      settings.morph = 1
      settings.fourD = true
      settings.trails = false
      geometry.update(
        snapshot(settings, kind: kind), size: CGSize(width: 390, height: 340), capacity: 32_768)
      let orbit = channelSegments(geometry)
      XCTAssertFalse(orbit.isEmpty)
      var previous = orbit
      for motion in Motion.allCases.dropFirst() {
        settings.channels[0].motion = motion
        geometry.update(
          snapshot(settings, kind: kind), size: CGSize(width: 390, height: 340), capacity: 32_768)
        let changed = channelSegments(geometry)
        XCTAssertNotEqual(
          changed, previous, "\(kind.title) must immediately reflect \(motion.rawValue).")
        previous = changed
      }
      settings.channels[0].motion = .orbit
      geometry.update(
        snapshot(settings, kind: kind), size: CGSize(width: 390, height: 340), capacity: 32_768)
      XCTAssertEqual(
        channelSegments(geometry), orbit, "Returning to Orbit must refresh cached paths.")
    }
  }

  func testGuideGeometryDoesNotChangeWhenOnlyPlaybackRateChanges() {
    var settings = OrbitalSettings()
    settings.morph = 1
    settings.channels[0].motion = .precession
    let geometry = SceneGeometry()
    geometry.update(
      snapshot(settings, kind: .spatial), size: CGSize(width: 390, height: 340), capacity: 32_768)
    let guide = channelSegments(geometry, dashedOnly: true)
    settings.channels[0].speed = 0
    settings.channels[0].frequency = 0.84
    geometry.update(
      snapshot(settings, kind: .spatial), size: CGSize(width: 390, height: 340), capacity: 32_768)
    XCTAssertEqual(channelSegments(geometry, dashedOnly: true), guide)
  }
}
