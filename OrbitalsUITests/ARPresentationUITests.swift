import XCTest

/// Simulator exercises the unsupported-device path without requesting camera access.
final class ARPresentationUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testUnsupportedARClosesBackToPausedCameraWithoutResettingIt() throws {
    try requireSimulator()
    let app = launchPausedFullScreen()
    let canvas = fullScreenCanvas(in: app)
    let originalCamera = canvas.value as? String ?? ""
    let zoom = app.buttons["camera-zoom-in"]
    requireHittable(zoom)
    zoom.tap()
    wait(
      NSPredicate(format: "value != %@", originalCamera), on: canvas,
      message: "A nondefault camera is established before entering AR")
    let adjustedCamera = canvas.value as? String

    openUnsupportedAR(in: app)
    closeAR(in: app)

    requireHittable(canvas)
    XCTAssertEqual(
      canvas.value as? String, adjustedCamera,
      "Closing unsupported AR must preserve full-screen framing and rotation.")
    XCTAssertEqual(app.buttons["fullscreen-play"].label, "Play")
    closeFullScreenAndAssertPausedClock(in: app)
  }

  @MainActor
  func testARControlsAndViewSelectionRemainAvailableWhenARIsUnsupported() throws {
    try requireSimulator()
    let app = launchPausedFullScreen()
    openUnsupportedAR(in: app)

    let motion = app.buttons["ar-motion-controls"]
    requireHittable(motion)
    motion.tap()
    let sheet = app.navigationBars["Motion control"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertTrue(app.scrollViews["motion-controls-scroll"].exists)
    let done = app.buttons["Done"]
    requireHittable(done)
    done.tap()
    wait(
      NSPredicate(format: "exists == false"), on: sheet, message: "The AR motion sheet dismisses")

    let picker = app.buttons["ar-view-picker"]
    requireHittable(picker)
    picker.tap()
    let retcon = app.buttons["Retcon torus"]
    requireHittable(retcon)
    retcon.tap()
    closeAR(in: app)

    let canvas = fullScreenCanvas(in: app)
    requireHittable(canvas)
    wait(
      NSPredicate(format: "label CONTAINS %@", "Retcon torus"), on: canvas,
      message: "The AR selection is retained by the full-screen projection")
    XCTAssertEqual(app.buttons["fullscreen-play"].label, "Play")
    closeFullScreenAndAssertPausedClock(in: app)
    XCTAssertTrue(
      app.segmentedControls["dimension-picker"].buttons["5D"].isSelected,
      "Choosing a temporal view from AR enables its required fifth dimension.")
  }

  private func requireSimulator() throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Unsupported AR presentation is a Simulator-specific flow.")
    #endif
  }

  @MainActor
  private func launchPausedFullScreen() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    XCTAssertTrue(app.buttons["transport-play"].waitForExistence(timeout: 10))
    let expand = app.buttons["visualization-expand"]
    requireHittable(expand)
    expand.tap()
    requireHittable(fullScreenCanvas(in: app))
    return app
  }

  @MainActor
  private func fullScreenCanvas(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "orbital-canvas-fullscreen").firstMatch
  }

  @MainActor
  private func openUnsupportedAR(in app: XCUIApplication) {
    let ar = app.buttons["visualization-ar"]
    requireHittable(ar)
    ar.tap()
    let fallback = app.descendants(matching: .any).matching(identifier: "ar-unavailable").firstMatch
    XCTAssertTrue(
      fallback.waitForExistence(timeout: 5), "Simulator explains that AR is unavailable.")
    XCTAssertFalse(
      app.buttons["ar-place"].exists, "Unsupported AR must not offer unusable placement.")
  }

  @MainActor
  private func closeAR(in app: XCUIApplication) {
    let close = app.buttons["ar-close"]
    requireHittable(close)
    close.tap()
    wait(NSPredicate(format: "exists == false"), on: close, message: "The AR presentation closes")
  }

  @MainActor
  private func closeFullScreenAndAssertPausedClock(in app: XCUIApplication) {
    let close = app.buttons["visualization-close"]
    requireHittable(close)
    close.tap()
    let play = app.buttons["transport-play"]
    requireHittable(play)
    XCTAssertEqual(play.label, "Play")
    let clock = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Simulation paused, 00:00.00")
    ).firstMatch
    XCTAssertTrue(clock.exists, "Entering and leaving AR must not advance a paused simulation.")
  }

  @MainActor
  private func requireHittable(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing element: \(element)")
    wait(
      NSPredicate(format: "hittable == true"), on: element,
      message: "Element is hittable: \(element)")
  }

  @MainActor
  private func wait(_ predicate: NSPredicate, on element: XCUIElement, message: String) {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, message)
  }
}
