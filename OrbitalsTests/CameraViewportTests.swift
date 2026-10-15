import XCTest

@testable import Orbitals

@MainActor
final class CameraViewportTests: XCTestCase {
  private func makeModel() -> OrbitModel {
    UserDefaults.standard.removeObject(forKey: "Orbitals.experiment.v1")
    let model = OrbitModel()
    model.reset()
    model.running = false
    return model
  }

  private func assertViewport(
    _ camera: ViewCamera, zoom: Double, panX: Double, panY: Double,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(camera.zoom, zoom, accuracy: 1e-12, file: file, line: line)
    XCTAssertEqual(camera.panX, panX, accuracy: 1e-12, file: file, line: line)
    XCTAssertEqual(camera.panY, panY, accuracy: 1e-12, file: file, line: line)
  }

  func testRotationPreservesZoomAndPanForEveryView() {
    let model = makeModel()
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      model.setViewport(zoom: 2.5, panX: 0.22, panY: -0.16)
      model.setCamera(yaw: 450, pitch: -100)
      XCTAssertEqual(model.camera.yaw, 90)
      XCTAssertEqual(model.camera.pitch, -85)
      assertViewport(model.camera, zoom: 2.5, panX: 0.22, panY: -0.16)
      XCTAssertEqual(model.renderSnapshot().camera, model.camera)
    }
  }

  func testViewportClampsLimitsAndPartialUpdatesPreserveOtherAxes() {
    let model = makeModel()
    model.setViewport(zoom: 12, panX: 4, panY: -3)
    assertViewport(model.camera, zoom: 6, panX: 1.5, panY: -1.5)
    model.setViewport(zoom: -1)
    assertViewport(model.camera, zoom: 0.25, panX: 1.5, panY: -1.5)
    model.setViewport(panX: 0.2)
    assertViewport(model.camera, zoom: 0.25, panX: 0.2, panY: -1.5)
    model.panCamera(dx: 0.3, dy: 0.25)
    assertViewport(model.camera, zoom: 0.25, panX: 0.5, panY: -1.25)
    model.panCamera(dx: -.greatestFiniteMagnitude, dy: .greatestFiniteMagnitude)
    assertViewport(model.camera, zoom: 0.25, panX: -1.5, panY: 1.5)
  }

  func testNonfiniteInputAndInvalidZoomFactorsLeaveCameraUntouched() {
    let model = makeModel()
    model.setCamera(yaw: 31, pitch: -12)
    model.setViewport(zoom: 1.8, panX: 0.1, panY: -0.3)
    let original = model.camera
    for invalid in [Double.nan, .infinity, -.infinity] {
      model.setCamera(yaw: invalid, pitch: 0)
      XCTAssertEqual(model.camera, original)
      model.setCamera(yaw: 0, pitch: invalid)
      XCTAssertEqual(model.camera, original)
      model.setViewport(zoom: invalid)
      XCTAssertEqual(model.camera, original)
      model.setViewport(zoom: 3, panX: invalid)
      XCTAssertEqual(model.camera, original)
      model.setViewport(panY: invalid)
      XCTAssertEqual(model.camera, original)
      model.panCamera(dx: invalid, dy: 0.4)
      XCTAssertEqual(model.camera, original)
      model.panCamera(dx: 0.4, dy: invalid)
      XCTAssertEqual(model.camera, original)
      model.zoomCamera(by: invalid)
      XCTAssertEqual(model.camera, original)
      model.zoomCamera(by: 2, anchor: SIMD2(invalid, 0))
      XCTAssertEqual(model.camera, original)
      model.zoomCamera(by: 2, anchor: SIMD2(0, invalid))
      XCTAssertEqual(model.camera, original)
    }
    model.zoomCamera(by: 0)
    XCTAssertEqual(model.camera, original)
    model.zoomCamera(by: -2)
    XCTAssertEqual(model.camera, original)
  }

  func testAnchoredZoomKeepsTouchedScenePointStationary() {
    let model = makeModel()
    model.setViewport(zoom: 1.25, panX: 0.1, panY: 0.1)
    let anchor = SIMD2<Double>(0.2, -0.1)
    let before = model.camera
    let scenePoint = (anchor - SIMD2(before.panX, before.panY)) / before.zoom
    model.zoomCamera(by: 3, anchor: anchor)
    let after = model.camera
    let projected = SIMD2(after.panX, after.panY) + scenePoint * after.zoom
    XCTAssertEqual(projected.x, anchor.x, accuracy: 1e-12)
    XCTAssertEqual(projected.y, anchor.y, accuracy: 1e-12)
    assertViewport(after, zoom: 3.75, panX: -0.1, panY: 0.5)
    model.zoomCamera(by: 1.0 / 3, anchor: anchor)
    assertViewport(model.camera, zoom: before.zoom, panX: before.panX, panY: before.panY)
  }

  func testAnchoredZoomUsesActualClampedRatioAtBothZoomLimits() {
    let model = makeModel()
    let anchor = SIMD2<Double>(0.2, -0.1)
    model.setViewport(zoom: 5, panX: 0.1, panY: 0)
    model.zoomCamera(by: 10, anchor: anchor)
    assertViewport(model.camera, zoom: 6, panX: 0.08, panY: 0.02)
    let atMaximum = model.camera
    model.zoomCamera(by: 2, anchor: anchor)
    XCTAssertEqual(model.camera, atMaximum, "At a zoom limit the pan must not drift.")
    model.setViewport(zoom: 0.5, panX: 0.1, panY: 0)
    model.zoomCamera(by: 0.01, anchor: anchor)
    assertViewport(model.camera, zoom: 0.25, panX: 0.15, panY: -0.05)
    let atMinimum = model.camera
    model.zoomCamera(by: 0.5, anchor: anchor)
    XCTAssertEqual(model.camera, atMinimum)
  }

  func testViewportIsIndependentForAllFiveViews() {
    let model = makeModel()
    var expected: [OrbitalViewKind: ViewCamera] = [:]
    for (index, view) in OrbitalViewKind.allCases.enumerated() {
      model.chooseView(view)
      model.setCamera(yaw: Double(index) * 17, pitch: Double(index) * -9)
      model.setViewport(
        zoom: 1 + Double(index) * 0.4, panX: Double(index) * 0.1,
        panY: Double(index) * -0.12)
      expected[view] = model.camera
    }
    for view in OrbitalViewKind.allCases.reversed() {
      model.chooseView(view)
      XCTAssertEqual(model.camera, expected[view])
      XCTAssertEqual(model.renderSnapshot().camera, expected[view])
    }
    XCTAssertEqual(model.dimension, 5)
  }

  func testResetCameraRestoresFramingAndOrientationWithoutChangingArchive() {
    let model = makeModel()
    let pitches: [OrbitalViewKind: Double] = [
      .spatial: 0, .cylinder: 10, .torus: 35, .tracks: 40, .retcon: 38,
    ]
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      for _ in 0..<3 { model.step() }
      let before = model.renderSnapshot()
      let revision = model.retconRevision
      model.setCamera(yaw: -50, pitch: -20)
      model.setViewport(zoom: 3.5, panX: -0.3, panY: 0.8)
      model.resetCamera()
      XCTAssertEqual(model.camera.yaw, view == .cylinder ? 16 : 0)
      XCTAssertEqual(model.camera.pitch, pitches[view])
      assertViewport(model.camera, zoom: 1, panX: 0, panY: 0)
      XCTAssertEqual(model.renderSnapshot().time, before.time)
      XCTAssertEqual(model.renderSnapshot().samples, before.samples)
      XCTAssertEqual(model.retconRevision, revision)
    }
  }

  func testFullResetAndPresetDiscardPreviousViewportCrops() {
    let model = makeModel()
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      model.setViewport(zoom: 4, panX: 0.4, panY: -0.4)
    }
    model.reset()
    model.running = false
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      assertViewport(model.camera, zoom: 1, panX: 0, panY: 0)
      model.setViewport(zoom: 3, panX: -0.2, panY: 0.3)
    }
    model.applyPreset("Spherical orbits")
    XCTAssertEqual(model.selectedView, .spatial)
    XCTAssertEqual(model.camera.yaw, 28)
    XCTAssertEqual(model.camera.pitch, 20)
    for view in OrbitalViewKind.allCases {
      model.chooseView(view)
      assertViewport(model.camera, zoom: 1, panX: 0, panY: 0)
    }
  }

  func testViewportChangesInvalidatePausedFrameWithoutAlteringMathOrTimeline() {
    let model = makeModel()
    model.chooseView(.retcon)
    for _ in 0..<15 { model.step() }
    let before = model.renderSnapshot()
    let revision = model.retconRevision
    let redraw = model.redrawKey
    model.setViewport(zoom: 2, panX: 0.1, panY: -0.1)
    model.panCamera(dx: 0.05, dy: -0.05)
    model.zoomCamera(by: 1.2)
    let after = model.renderSnapshot()
    XCTAssertGreaterThan(model.redrawKey, redraw)
    XCTAssertEqual(after.settings, before.settings)
    XCTAssertEqual(after.time, before.time)
    XCTAssertEqual(after.samples, before.samples)
    XCTAssertEqual(model.retconRevision, revision)
    XCTAssertFalse(model.running)
  }
}
