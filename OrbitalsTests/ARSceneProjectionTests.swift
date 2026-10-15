import XCTest
import simd

@testable import Orbitals

@MainActor
final class ARSceneProjectionTests: XCTestCase {
  private let viewport = CGSize(width: 400, height: 300)

  private func transform(scale: Float = 1, translation: SIMD3<Float> = .zero)
    -> simd_float4x4
  {
    var matrix = matrix_identity_float4x4
    matrix.columns.0.x = scale
    matrix.columns.1.y = scale
    matrix.columns.2.z = scale
    matrix.columns.3 = SIMD4(translation, 1)
    return matrix
  }

  private var perspective: simd_float4x4 {
    let near: Float = 0.1
    let far: Float = 10
    return simd_float4x4(
      SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
      SIMD4(0, 0, far / (near - far), -1),
      SIMD4(0, 0, near * far / (near - far), 0))
  }

  private func snapshot(_ kind: OrbitalViewKind) -> RenderSnapshot {
    var settings = OrbitalSettings()
    settings.fourD = true
    settings.morph = 1
    let samples = (0...60).map { index in
      let time = Double(index) / 30
      return TimelineSample(
        t: time, points: OrbitalMath.pointsAt(time, settings: settings), segment: 0)
    }
    return RenderSnapshot(
      settings: settings, time: 2.3, samples: samples, kind: kind,
      camera: ViewCamera(yaw: 17, pitch: 31), horizon: 3, inspectionOffset: 0,
      planeIndices: [0, 1], loopEnabled: false, loopProgram: LoopProgram(), loopEpoch: 0,
      loopOrigins: [0, 0, 0], retconPhase: 30, ghostStrength: 0.4, trailCutoff: 0)
  }

  private func assertSameSegments(
    _ actual: [PhosphorSegment], _ expected: [PhosphorSegment],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (actual, expected) in zip(actual, expected) {
      XCTAssertEqual(actual.start, expected.start, file: file, line: line)
      XCTAssertEqual(actual.end, expected.end, file: file, line: line)
      XCTAssertEqual(actual.color, expected.color, file: file, line: line)
      XCTAssertEqual(actual.style, expected.style, file: file, line: line)
      XCTAssertEqual(actual.detail, expected.detail, file: file, line: line)
    }
  }

  func testViewportMapsMetalCoordinatesToTopLeftOrigin() {
    let projection = ARSceneProjection(
      viewProjection: matrix_identity_float4x4, modelTransform: matrix_identity_float4x4)
    XCTAssertEqual(projection.project(Vec3(0, 0, 0.5), viewport: viewport), SIMD2(200, 150))
    XCTAssertEqual(projection.project(Vec3(-1, 1, 0.5), viewport: viewport), SIMD2(0, 0))
    XCTAssertEqual(projection.project(Vec3(1, -1, 0.5), viewport: viewport), SIMD2(400, 300))
  }

  func testAnchorTransformPrecedesCameraProjectionAndViewportScaling() throws {
    let model = transform(scale: 0.5, translation: SIMD3(0.5, 0.25, 0.5))
    let camera = transform(scale: 0.5, translation: SIMD3(-0.25, 0, 0))
    let projection = ARSceneProjection(viewProjection: camera, modelTransform: model)
    let result = try XCTUnwrap(projection.project(Vec3(1, 0, 0), viewport: viewport))
    // Model point -> (1, .25, .5), camera -> (.25, .125, .25).
    XCTAssertEqual(result.x, 250, accuracy: 0.0001)
    XCTAssertEqual(result.y, 131.25, accuracy: 0.0001)
    let doubled = try XCTUnwrap(
      projection.project(Vec3(1, 0, 0), viewport: CGSize(width: 800, height: 600)))
    XCTAssertEqual(doubled, result * 2)
  }

  func testPerspectiveForeshortensAndRejectsBehindNearAndFarPoints() throws {
    let projection = ARSceneProjection(
      viewProjection: perspective, modelTransform: matrix_identity_float4x4)
    let nearby = try XCTUnwrap(projection.project(Vec3(1, 1, -2), viewport: viewport))
    let distant = try XCTUnwrap(projection.project(Vec3(1, 1, -4), viewport: viewport))
    XCTAssertEqual(nearby, SIMD2(300, 75))
    XCTAssertEqual(distant, SIMD2(250, 112.5))
    for z in [-11.0, -0.05, 0, 2] {
      XCTAssertNil(projection.project(Vec3(0, 0, z), viewport: viewport))
    }
    XCTAssertNotNil(projection.project(Vec3(0, 0, -0.101), viewport: viewport))
    XCTAssertNotNil(projection.project(Vec3(0, 0, -9.99), viewport: viewport))
  }

  func testInvalidInputsNeverReachTheGPU() {
    let identity = ARSceneProjection(
      viewProjection: matrix_identity_float4x4, modelTransform: matrix_identity_float4x4)
    for invalid in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
      for component in 0..<3 {
        var point = Vec3(0, 0, 0.5)
        point[component] = invalid
        XCTAssertNil(identity.project(point, viewport: viewport))
      }
    }
    for size in [
      CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.infinity, height: 100),
    ] {
      XCTAssertNil(identity.project(Vec3(0, 0, 0.5), viewport: size))
    }
    var invalidMatrix = matrix_identity_float4x4
    invalidMatrix.columns.0.x = .nan
    XCTAssertNil(
      ARSceneProjection(viewProjection: invalidMatrix, modelTransform: matrix_identity_float4x4)
        .project(Vec3(0, 0, 0.5), viewport: viewport))
  }

  func testEveryARViewIgnoresInstrumentCameraAndRestoresNormalRendering() {
    let geometry = SceneGeometry()
    let projection = ARSceneProjection(
      viewProjection: matrix_identity_float4x4,
      modelTransform: transform(scale: 0.1, translation: SIMD3(0, 0, 0.5)))
    for kind in OrbitalViewKind.allCases {
      let original = snapshot(kind)
      geometry.update(original, size: viewport, capacity: 32_768)
      let normal = geometry.segments
      geometry.update(original, size: viewport, capacity: 32_768, arProjection: projection)
      let anchored = geometry.segments
      XCTAssertFalse(anchored.isEmpty)
      var movedCamera = original
      movedCamera.camera = ViewCamera(yaw: -123, pitch: 74, zoom: 4, panX: 0.7, panY: -0.8)
      geometry.update(movedCamera, size: viewport, capacity: 32_768, arProjection: projection)
      assertSameSegments(geometry.segments, anchored)
      geometry.update(original, size: viewport, capacity: 32_768)
      assertSameSegments(geometry.segments, normal)
    }
  }

  func testClippedSectionsDoNotPoisonVisibleDashesInAnyView() {
    let geometry = SceneGeometry()
    let projection = ARSceneProjection(
      viewProjection: perspective,
      modelTransform: transform(scale: 0.2, translation: SIMD3(0, 0, -0.25)))
    for kind in OrbitalViewKind.allCases {
      geometry.update(snapshot(kind), size: viewport, capacity: 32_768, arProjection: projection)
      XCTAssertFalse(geometry.segments.isEmpty, "\(kind.title) must retain its visible sections.")
      let dashed = geometry.segments.filter { $0.style.z > 0 }
      XCTAssertFalse(dashed.isEmpty, "\(kind.title) must retain visible dashed geometry.")
      // Tracks are solid. Their only dashes are independent one-segment axes,
      // each correctly starting at offset zero. The other views have dashed
      // multipoint trajectories that must continue accumulating after clipping.
      if kind != .tracks {
        XCTAssertTrue(
          dashed.contains { $0.style.w > 0 },
          "\(kind.title) must resume cumulative dash offsets in visible trajectories.")
      }
      for segment in geometry.segments {
        for value in [segment.start.x, segment.start.y, segment.end.x, segment.end.y] {
          XCTAssertTrue(value.isFinite, "\(kind.title) emitted a nonfinite endpoint.")
        }
        for component in 0..<4 {
          XCTAssertTrue(
            segment.style[component].isFinite, "\(kind.title) emitted a nonfinite style.")
          XCTAssertTrue(
            segment.color[component].isFinite, "\(kind.title) emitted a nonfinite color.")
        }
      }
      let behind = ARSceneProjection(
        viewProjection: perspective,
        modelTransform: transform(scale: 0.1, translation: SIMD3(0, 0, 2)))
      geometry.update(snapshot(kind), size: viewport, capacity: 32_768, arProjection: behind)
      XCTAssertTrue(
        geometry.segments.isEmpty, "\(kind.title) must cull geometry wholly behind the camera.")
    }
  }

  func testSpatialARUsesTheSameFourDimensionalProjectionBeforeAnchoring() throws {
    let geometry = SceneGeometry()
    let snapshot = snapshot(.spatial)
    let projection = ARSceneProjection(
      viewProjection: perspective,
      modelTransform: transform(scale: 0.1, translation: SIMD3(0, 0, -2)))
    geometry.update(snapshot, size: viewport, capacity: 32_768, arProjection: projection)
    let cyan = SIMD3<Float>(0.1, 0.93, 1)
    let node = try XCTUnwrap(
      geometry.segments.first {
        $0.start == $0.end && SIMD3($0.color.x, $0.color.y, $0.color.z) == cyan
      })
    var settings = snapshot.settings
    settings.yaw = 0
    settings.pitch = 0
    let point = OrbitalMath.pointAt(snapshot.time, index: 0, settings: settings)
    let expected = projection.project(
      OrbitalMath.project(point, settings: settings), viewport: viewport)
    XCTAssertEqual(node.start, expected)
  }

  func testOnlyCylinderNowRingChangesToLuminousWhite() {
    let geometry = SceneGeometry()
    for kind in [OrbitalViewKind.cylinder, .torus] {
      var snapshot = snapshot(kind)
      snapshot.settings.mesh = false
      snapshot.settings.axes = false
      geometry.update(snapshot, size: viewport, capacity: 32_768)
      let white = geometry.segments.filter { $0.color == SIMD4<Float>(1, 1, 1, 1) }
      XCTAssertEqual(white.count, kind == .cylinder ? 64 : 0)
      for segment in white {
        XCTAssertEqual(segment.style.y, Float(snapshot.settings.glow))
      }
    }
  }
}
