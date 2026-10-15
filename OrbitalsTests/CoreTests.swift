import XCTest
import simd

@testable import Orbitals

final class CoreTests: XCTestCase {
  private func assertNear(
    _ a: Vec4, _ b: Vec4, accuracy: Double = 1e-9,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertLessThanOrEqual(simd_distance(a, b), accuracy, file: file, line: line)
  }

  private func assertNear(
    _ a: Vec3, _ b: Vec3, accuracy: Double = 1e-9,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertLessThanOrEqual(simd_distance(a, b), accuracy, file: file, line: line)
  }

  func testDefaultsAndCodableRoundTrip() throws {
    let settings = OrbitalSettings()
    XCTAssertEqual(settings.radius, 2)
    XCTAssertEqual(settings.morph, 0)
    XCTAssertFalse(settings.fourD)
    XCTAssertEqual(settings.channels.map(\.phase), [0, 120, 240])
    XCTAssertTrue(
      settings.channels.allSatisfy {
        $0.motion == .orbit && $0.frequency == 0.12 && $0.amplitude == 0.7 && $0.speed == 1
      })
    let data = try JSONEncoder().encode(settings)
    XCTAssertEqual(try JSONDecoder().decode(OrbitalSettings.self, from: data), settings)
    let sample = TimelineSample(
      t: 1, points: OrbitalMath.pointsAt(1, settings: settings), segment: 3)
    XCTAssertEqual(
      try JSONDecoder().decode(TimelineSample.self, from: JSONEncoder().encode(sample)), sample)
  }

  func testCircleSphereMorphPreservesRadius() {
    var s = OrbitalSettings()
    for index in 0..<301 {
      let theta = Double(index) * 0.29
      let latitude = Double(index % 101) * .pi / 100 - .pi / 2
      s.radius = 0.5 + Double(index % 251) / 100
      s.morph = 0
      let circle = OrbitalMath.surface(theta: theta, latitude: latitude, wAngle: 0, settings: s)
      XCTAssertEqual(circle.z, 0)
      XCTAssertEqual(simd_length(circle), s.radius, accuracy: 1e-10)
      s.morph = Double(index % 101) / 100
      let v = OrbitalMath.surface(theta: theta, latitude: latitude, wAngle: 0, settings: s)
      XCTAssertEqual(simd_length(v), s.radius, accuracy: 1e-10)
      s.morph += 1e-7
      XCTAssertLessThan(
        simd_distance(
          v, OrbitalMath.surface(theta: theta, latitude: latitude, wAngle: 0, settings: s)), 1e-5)
      s.morph = 1
      XCTAssertEqual(
        OrbitalMath.surface(theta: theta, latitude: .pi / 2, wAngle: 0, settings: s).z, s.radius,
        accuracy: 1e-10)
    }
  }

  func testFourDimensionalRotationsPreserveDistancesAndInvert() {
    var s = OrbitalSettings()
    s.fourD = true
    let a = Vec4(1.7, -0.8, 2.2, -1.9)
    let b = Vec4(-0.3, 1.1, 0.6, 2.7)
    for index in 0..<500 {
      s.xw = Double(index) * 0.53
      s.yw = Double(index) * -0.71
      s.zw = Double(index) * 1.13
      let rotated = OrbitalMath.rotate4(a, settings: s)
      XCTAssertEqual(simd_length(rotated), simd_length(a), accuracy: 1e-10)
      XCTAssertEqual(
        OrbitalMath.distance(rotated, OrbitalMath.rotate4(b, settings: s)), simd_distance(a, b),
        accuracy: 1e-10)
      let angle = Double(index) * 0.07
      let turned = OrbitalMath.rotatePlane(a, i: 0, j: 3, angle: angle)
      assertNear(OrbitalMath.rotatePlane(turned, i: 0, j: 3, angle: -angle), a)
    }
  }

  func testMeshIsOnHypersphere() {
    var s = OrbitalSettings()
    s.fourD = true
    s.morph = 1
    let points = OrbitalMath.meshLines(settings: s).flatMap { $0 }
    XCTAssertTrue(points.contains { abs($0.w) > 1 })
    for point in points { XCTAssertEqual(simd_length(point), s.radius, accuracy: 1e-10) }
  }

  func testAllMotionsRemainFiniteBoundedAndProjectionSafe() {
    for motion in Motion.allCases {
      for index in 0..<400 {
        var s = OrbitalSettings()
        s.fourD = index.isMultiple(of: 2)
        s.morph = Double(index % 101) / 100
        s.radius = 0.5 + Double(index % 251) / 100
        s.yaw = Double(index) * 13.13
        s.pitch = Double(index) * 2.71
        s.xw = Double(index) * 3.7
        s.yw = Double(index) * 6.1
        s.zw = Double(index) * -11.9
        let amplitude = Double(index % 101) / 100
        for channel in s.channels.indices {
          s.channels[channel].motion = motion
          s.channels[channel].amplitude = amplitude
          s.channels[channel].speed = Double((index * 37) % 301) / 100
          s.channels[channel].frequency = 0.01 + Double((index * 11) % 100) / 100
        }
        for channel in s.channels.indices {
          let point = OrbitalMath.pointAt(Double(index) * 1.321, index: channel, settings: s)
          XCTAssertTrue((0..<4).allSatisfy { point[$0].isFinite })
          XCTAssertLessThanOrEqual(simd_length(point), s.radius + 1e-10)
          if [.orbit, .pendulum, .precession].contains(motion) {
            XCTAssertEqual(simd_length(point), s.radius, accuracy: 1e-10)
          }
          if motion == .lissajous {
            XCTAssertLessThanOrEqual(simd_length(point), s.radius * amplitude + 1e-10)
          }
          if motion == .breathing {
            XCTAssertGreaterThanOrEqual(
              simd_length(point), s.radius * (1 - 0.9 * amplitude) - 1e-10)
          }
          let projected = OrbitalMath.project(point, settings: s)
          XCTAssertTrue((0..<3).allSatisfy { projected[$0].isFinite })
          XCTAssertLessThanOrEqual(
            simd_length(projected), s.radius * (s.fourD ? 3 / sqrt(8) : 1) + 1e-10)
        }
      }
    }
  }

  func testPendulumExtremaAndPlane() {
    var s = OrbitalSettings()
    s.morph = 1
    s.channels[0] = Channel(motion: .pendulum, amplitude: 1, frequency: 1)
    for t in [0.25, 0.75] {
      assertNear(
        OrbitalMath.pointAt(t - 1e-5, index: 0, settings: s),
        OrbitalMath.pointAt(t + 1e-5, index: 0, settings: s))
    }
    for index in 0..<100 {
      let point = OrbitalMath.pointAt(Double(index) / 100, index: 0, settings: s)
      XCTAssertEqual(-sin(0.7) * point.y + cos(0.7) * point.z, 0, accuracy: 1e-10)
    }
  }

  func testKnownTriangleAndLinkedChannels() {
    var s = OrbitalSettings()
    XCTAssertEqual(
      OrbitalMath.distance(
        OrbitalMath.pointAt(0, index: 0, settings: s), OrbitalMath.pointAt(0, index: 1, settings: s)
      ), 2 * sqrt(3), accuracy: 1e-10)
    for motion in Motion.allCases {
      s.morph = 1
      s.fourD = true
      s.channels = Array(repeating: Channel(motion: motion, phase: 120), count: 3)
      for t in [0.0, 1, 7.4, 111] {
        let points = OrbitalMath.pointsAt(t, settings: s)
        assertNear(points[0], points[1])
        assertNear(points[1], points[2])
      }
    }
  }

  func testRecorderUsesFixedTicksAndRetainsOnlyThirtySeconds() {
    let s = OrbitalSettings()
    var recorder = TimelineRecorder()
    recorder.record(at: 0, settings: s)
    recorder.record(at: 0.5, settings: s)
    XCTAssertEqual(recorder.samples.count, 31)
    for (index, sample) in recorder.samples.enumerated() {
      XCTAssertEqual(sample.t, Double(index) / 60, accuracy: 1e-10)
      XCTAssertEqual(sample.points, OrbitalMath.pointsAt(sample.t, settings: s))
    }
    recorder.record(at: 90, settings: s)
    XCTAssertLessThanOrEqual(recorder.samples.count, 1_801)
    XCTAssertGreaterThanOrEqual(recorder.samples.first!.t, 60 - 1e-9)
    XCTAssertEqual(recorder.samples.last!.t, 90, accuracy: 1e-9)
  }

  func testPausedEditsNeverRewriteArchiveAndResumeStartsSegment() {
    var s = OrbitalSettings()
    var recorder = TimelineRecorder()
    recorder.record(at: 0, settings: s)
    recorder.record(at: 1, settings: s)
    let original = recorder.samples
    let segment = recorder.segment
    s.channels[0].frequency = 0.91
    recorder.record(at: 1, settings: s)
    XCTAssertEqual(recorder.samples, original)
    XCTAssertEqual(recorder.segment, segment + 1)
    recorder.record(at: 1 + 1.0 / 60, settings: s)
    XCTAssertEqual(Array(recorder.samples.prefix(original.count)), original)
    XCTAssertEqual(TimelineMath.splitSegments(recorder.samples).count, 2)
    XCTAssertEqual(recorder.samples.last!.points, OrbitalMath.pointsAt(1 + 1.0 / 60, settings: s))
  }

  func testOpticalChangesDoNotSplitArchiveAndClockResetClearsIt() {
    var s = OrbitalSettings()
    var recorder = TimelineRecorder()
    recorder.record(at: 0, settings: s)
    recorder.record(at: 2, settings: s)
    let segment = recorder.segment
    s.glow = 0.1
    s.yaw = 76
    s.pitch = -12
    s.mesh = false
    s.trails = false
    recorder.record(at: 3, settings: s)
    XCTAssertEqual(recorder.segment, segment)
    recorder.record(at: 0, settings: s)
    XCTAssertEqual(recorder.samples.count, 1)
    XCTAssertEqual(recorder.samples.first!.t, 0)
    recorder.clear()
    XCTAssertTrue(recorder.samples.isEmpty)
    XCTAssertEqual(recorder.lastTime, -.infinity)
  }

  func testRecordedCursorReturnsRealSnapshotAndForecastHitsEndpoint() {
    var recorder = TimelineRecorder()
    let s = OrbitalSettings()
    recorder.record(at: 2, settings: s)
    recorder.record(at: 3, settings: s)
    XCTAssertNil(TimelineMath.recordedAt(recorder.samples, time: 1))
    XCTAssertNil(TimelineMath.recordedAt(recorder.samples, time: 4))
    let snapshot = TimelineMath.recordedAt(recorder.samples, time: 2.119)!
    XCTAssertLessThanOrEqual(snapshot.t, 2.119)
    XCTAssertTrue(recorder.samples.contains(snapshot))
    let forecast = TimelineMath.forecast(now: 3, horizon: 1.019, settings: s)
    XCTAssertEqual(forecast.first!.t, 3)
    XCTAssertEqual(forecast.last!.t, 4.019, accuracy: 1e-12)
    XCTAssertEqual(forecast.last!.points, OrbitalMath.pointsAt(4.019, settings: s))
  }

  func testTorusClosureJoinsEndpointsAndStaysInTube() {
    let end = Vec4(2, 0.4, -0.5, 0.3)
    let previous = Vec4(1.7, -1, 0.3, 0.2)
    let start = Vec4(-0.7, 1.6, 0.9, -0.8)
    let next = Vec4(-0.5, 0.1, 2, 0.5)
    for scale in [0.0, 3, 50, 1_000] {
      let bridge = TorusMath.closureBridge(
        end: end, beforeEnd: previous, start: start, afterStart: next, tangentScale: scale)
      assertNear(bridge.first!, TorusMath.projectToTorus(end, offset: 8, horizon: 8))
      assertNear(bridge.last!, TorusMath.projectToTorus(start, offset: -8, horizon: 8))
      for point in bridge {
        XCTAssertLessThanOrEqual(
          hypot(hypot(point.x, point.z) - TorusMath.torusRadius, point.y),
          TorusMath.tubeRadius + 1e-9)
      }
    }
  }

  func testAllTracksCloseInPositionAndTangent() {
    for fourD in [false, true] {
      for motion in Motion.allCases {
        var s = OrbitalSettings()
        s.fourD = fourD
        s.morph = 0.63
        s.xw = 71
        s.yw = 29
        s.zw = -88
        for index in s.channels.indices { s.channels[index].motion = motion }
        for channel in s.channels.indices {
          assertNear(
            TrackMath.trackPoint(phase: 0, index: channel, settings: s),
            TrackMath.trackPoint(phase: 1, index: channel, settings: s))
          let epsilon = 1e-6
          func tangent(_ phase: Double) -> Vec3 {
            (TrackMath.trackPoint(phase: phase + epsilon, index: channel, settings: s)
              - TrackMath.trackPoint(phase: phase - epsilon, index: channel, settings: s))
              / (2 * epsilon)
          }
          assertNear(tangent(0), tangent(1), accuracy: 1e-6)
        }
      }
    }
  }

  func testSpeedAffectsNodesNotTracksAndNodesMatchPhysicalCoordinates() {
    for motion in Motion.allCases {
      var s = OrbitalSettings()
      s.fourD = true
      s.morph = 0.8
      s.xw = 73
      s.yw = -19
      s.zw = 43
      for index in s.channels.indices {
        s.channels[index].motion = motion
        s.channels[index].phase = Double(33 + index * 117)
        s.channels[index].frequency = 0.37
        s.channels[index].speed = 1.28
      }
      var fast = s
      for index in fast.channels.indices {
        fast.channels[index].frequency = 0.93
        fast.channels[index].speed = 2.8
      }
      XCTAssertEqual(TrackMath.trackShapeKey(s), TrackMath.trackShapeKey(fast))
      for index in s.channels.indices {
        assertNear(
          TrackMath.trackPoint(phase: 0.31, index: index, settings: s),
          TrackMath.trackPoint(phase: 0.31, index: index, settings: fast))
        for t in [0.0, 0.3, 2.7, 17.9] {
          let track = TrackMath.trackPoint(
            phase: TrackMath.naturalPhase(t, index: index, settings: s), index: index, settings: s)
          let cross = TorusMath.projectCrossSection(
            OrbitalMath.pointAt(t, index: index, settings: s))
          XCTAssertEqual(hypot(track.x, track.z) - TorusMath.torusRadius, cross.x, accuracy: 1e-9)
          XCTAssertEqual(track.y, cross.y, accuracy: 1e-9)
        }
      }
    }
  }

  func testLoopPresetsRepeatSettingsAndNodes() {
    for program in LoopProgram.presets.values {
      for motion in Motion.allCases {
        var s = OrbitalSettings()
        s.fourD = true
        s.morph = 1
        for index in s.channels.indices { s.channels[index].motion = motion }
        for u in [0.0, 0.13, 0.43, 0.99] {
          let a = TrackMath.loopSettings(base: s, u: u, program: program)
          let b = TrackMath.loopSettings(base: s, u: u + 1, program: program)
          XCTAssertEqual(a.radius, b.radius, accuracy: 1e-10)
          for index in s.channels.indices {
            let pa = TrackMath.loopPhase(u: u, index: index, origin: 0.2, program: program)
            let pb = TrackMath.loopPhase(u: u + 1, index: index, origin: 0.2, program: program)
            assertNear(
              TrackMath.trackPoint(phase: pa, index: index, settings: a),
              TrackMath.trackPoint(phase: pb, index: index, settings: b))
          }
        }
      }
    }
  }

  func testLoopPaceNonnegativeAndModulationBounded() {
    for depth in [0.0, 0.4, 1] {
      var program = LoopProgram()
      program.depth = depth
      for pace in [0.0, 1, 3, 6] {
        program.pace = pace
        for index in 0..<3 {
          XCTAssertEqual(
            TrackMath.loopPhase(u: 1, index: index, origin: 0.4, program: program)
              - TrackMath.loopPhase(u: 0, index: index, origin: 0.4, program: program),
            program.laps + Double(index), accuracy: 1e-10)
          for tick in 0...100 {
            let u = Double(tick) / 100
            let epsilon = 1e-6
            let speed =
              (TrackMath.loopPhase(u: u + epsilon, index: index, origin: 0, program: program)
                - TrackMath.loopPhase(u: u - epsilon, index: index, origin: 0, program: program))
              / (2 * epsilon)
            XCTAssertGreaterThanOrEqual(speed, -1e-8)
          }
        }
      }
    }
    var program = LoopProgram()
    program.depth = 1
    for radius in [0.5, 1.7, 3] {
      for amplitude in [0.0, 0.3, 1] {
        var settings = OrbitalSettings()
        settings.radius = radius
        for index in settings.channels.indices { settings.channels[index].amplitude = amplitude }
        let original = settings
        for tick in 0...100 {
          let adjusted = TrackMath.loopSettings(
            base: settings, u: Double(tick) / 100, program: program)
          XCTAssertGreaterThanOrEqual(adjusted.radius, 0.5 - 1e-10)
          XCTAssertLessThanOrEqual(adjusted.radius, 3 + 1e-10)
          XCTAssertTrue(
            adjusted.channels.allSatisfy { $0.amplitude >= -1e-10 && $0.amplitude <= 1 + 1e-10 })
        }
        XCTAssertEqual(settings, original)
      }
    }
  }

  func testCameraRotationPreservesDistancesAndCylinderFits() {
    let a = Vec3(1, 0.4, -0.8)
    let b = Vec3(-2, 0.7, 0.6)
    for yaw in [-180.0, -75, 0, 16, 75, 180] {
      for pitch in [-85.0, -65, 0, 10, 65, 85] {
        XCTAssertEqual(
          simd_distance(
            CameraMath.rotate(a, yaw: yaw, pitch: pitch),
            CameraMath.rotate(b, yaw: yaw, pitch: pitch)), simd_distance(a, b), accuracy: 1e-10)
        let scale = CameraMath.cylinderScale(width: 250, height: 245, yaw: yaw, pitch: pitch)
        for x in [-2.8, 2.8] {
          for tick in 0..<64 {
            let angle = Double(tick) / 64 * OrbitalMath.tau
            let v = CameraMath.rotate(
              Vec3(x, 1.2 * cos(angle), 1.2 * sin(angle)), yaw: yaw, pitch: pitch)
            XCTAssertLessThanOrEqual(abs(v.x) * scale, 103 + 1e-8)
            XCTAssertLessThanOrEqual(abs(v.y) * scale, 78.5 + 1e-8)
          }
        }
      }
    }
  }

  func testRetconRewritesPastAndFutureWithoutChangingArchive() {
    let originalSettings = OrbitalSettings()
    var recorder = TimelineRecorder()
    recorder.record(at: 0, settings: originalSettings)
    recorder.record(at: 2, settings: originalSettings)
    let archive = recorder.samples
    var branch = RetconBranch()
    branch.update(archive: archive, settings: originalSettings)
    let revised = RetconMath.settings(base: originalSettings, phaseShift: 30)
    branch.update(archive: archive, settings: revised)
    XCTAssertEqual(branch.revision, 2)
    XCTAssertEqual(recorder.samples, archive)
    for (original, rewritten) in zip(archive, branch.samples) {
      XCTAssertEqual(original.t, rewritten.t)
      XCTAssertEqual(rewritten.points, OrbitalMath.pointsAt(original.t, settings: revised))
      XCTAssertEqual(rewritten.segment, 0)
    }
    XCTAssertNotEqual(branch.samples[0].points, archive[0].points)
    XCTAssertNotEqual(
      TimelineMath.forecast(now: 2, horizon: 1, settings: originalSettings),
      TimelineMath.forecast(now: 2, horizon: 1, settings: revised))
    let deltas = RetconMath.rewriteDistances(original: archive[0], rewritten: branch.samples[0])!
    XCTAssertTrue(deltas.allSatisfy { $0 > 0 })
    XCTAssertEqual(originalSettings.channels.map(\.phase), [0, 120, 240])
    XCTAssertEqual(
      RetconMath.settings(base: originalSettings, phaseShift: -390).channels.map(\.phase),
      [330, 90, 210])
  }

  func testRetconOpticalChangesKeepRevisionAndArchiveGenerationResets() {
    var settings = OrbitalSettings()
    var branch = RetconBranch()
    let archive = TimelineMath.forecast(now: 0, horizon: 1, settings: settings)
    branch.update(archive: archive, settings: settings)
    let originalBranch = branch.samples
    settings.yaw = 120
    settings.glow = 0.2
    settings.mesh = false
    branch.update(archive: archive, settings: settings)
    XCTAssertEqual(branch.revision, 1)
    XCTAssertEqual(branch.samples, originalBranch)
    settings.radius = 1.3
    branch.update(archive: archive, settings: settings)
    XCTAssertEqual(branch.revision, 2)
    branch.update(archive: archive, settings: settings, archiveGeneration: 1)
    XCTAssertEqual(branch.revision, 1)
    branch.update(archive: [], settings: settings, archiveGeneration: 2)
    XCTAssertTrue(branch.samples.isEmpty)
    XCTAssertNil(RetconMath.rewriteDistances(original: nil, rewritten: archive.first))
  }
}
