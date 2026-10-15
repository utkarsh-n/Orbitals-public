import XCTest

final class MotionControlUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testMotionShortcutStaysAvailableAfterScrollingAndResetsFullScreenAlignment() {
    let app = launchPausedApp()
    let dashboard = app.scrollViews["dashboard-scroll"]
    requireHittable(dashboard)
    for _ in 0..<3 { scrollGutter(dashboard, towardBottom: true) }

    let shortcut = app.buttons["motion-controls-open"]
    requireHittable(shortcut)
    XCTAssertLessThan(shortcut.frame.midX, app.frame.midX, "Motion controls belong at top left.")
    shortcut.tap()
    XCTAssertTrue(app.navigationBars["Motion control"].waitForExistence(timeout: 5))
    dismissMotionSheet(in: app)

    let expand = app.buttons["visualization-expand"]
    reveal(expand, in: dashboard)
    expand.tap()
    let canvas = app.descendants(matching: .any).matching(
      identifier: "orbital-canvas-fullscreen"
    ).firstMatch
    requireHittable(canvas)
    let originalCamera = canvas.value as? String
    let zoom = app.buttons["camera-zoom-in"]
    requireHittable(zoom)
    zoom.tap()
    wait(
      NSPredicate(format: "value != %@", originalCamera ?? ""), on: canvas,
      message: "Zoom changes the camera before resetting alignment")

    let fullScreenShortcut = app.buttons["fullscreen-motion-controls-open"]
    requireHittable(fullScreenShortcut)
    XCTAssertLessThan(fullScreenShortcut.frame.midX, app.frame.midX)
    fullScreenShortcut.tap()
    XCTAssertTrue(app.navigationBars["Motion control"].waitForExistence(timeout: 5))
    let alignment = app.buttons["motion-reset-alignment"]
    requireHittable(alignment)
    alignment.tap()
    dismissMotionSheet(in: app)
    requireHittable(canvas)
    XCTAssertEqual(canvas.value as? String, originalCamera, "Reset alignment restores the camera.")
    XCTAssertEqual(app.buttons["fullscreen-play"].label, "Play")
  }

  @MainActor
  func testMotionChoicesUpdatePausedCoordinatesAndResetDials() {
    let app = launchPausedApp()
    openMotionSheet(in: app)
    let scroll = app.scrollViews["motion-controls-scroll"]
    requireHittable(scroll)
    var lastDescription = ""
    // Lissajous is last so its origin at t = 0 can verify the rendered model changed.
    for name in ["Orbit", "Pendulum", "Precession", "Breathing", "Lissajous"] {
      let choice = scroll.buttons["motion-choice-\(name)"]
      reveal(choice, in: scroll)
      choice.tap()
      wait(NSPredicate(format: "selected == true"), on: choice, message: "\(name) becomes selected")
      let description = scroll.staticTexts["motion-mode-description"]
      XCTAssertTrue(description.exists)
      XCTAssertFalse(description.label.isEmpty)
      XCTAssertNotEqual(
        description.label, lastDescription, "The explanation follows the chosen motion.")
      lastDescription = description.label
    }
    dismissMotionSheet(in: app)

    let x = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Channel A, X "))
      .firstMatch
    reveal(x, in: app.scrollViews["dashboard-scroll"])
    XCTAssertEqual(
      x.label, "Channel A, X 0.000",
      "Choosing Lissajous changes live coordinates while paused; the default Orbit has X = 2.")
    XCTAssertEqual(app.buttons["transport-play"].label, "Play")

    openMotionSheet(in: app)
    let speed = scroll.sliders["Speed, linear control"]
    reveal(speed, in: scroll)
    let originalSpeed = speed.value as? String ?? ""
    speed.adjust(toNormalizedSliderPosition: 0.8)
    wait(NSPredicate(format: "value != %@", originalSpeed), on: speed, message: "Speed changes")
    let reset = app.buttons["motion-reset-dials"]
    requireHittable(reset)
    reset.tap()
    let orbit = scroll.buttons["motion-choice-Orbit"]
    wait(
      NSPredicate(format: "selected == true"), on: orbit,
      message: "Reset restores the default motion")
    reveal(speed, in: scroll)
    XCTAssertEqual(numericValue(speed), 1, accuracy: 0.001, "Reset restores the speed multiplier.")
    dismissMotionSheet(in: app)
    XCTAssertEqual(
      app.buttons["transport-play"].label, "Play", "Resetting dials preserves transport state.")
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Simulation paused, 00:00.00")
      ).firstMatch.exists,
      "Mode changes and dial reset must not advance the clock.")
  }

  @MainActor
  func testHarmonicPresetPopulatesAllChannelsAndRemainsEditable() {
    let app = launchPausedApp()
    openMotionSheet(in: app)
    let scroll = app.scrollViews["motion-controls-scroll"]
    let harmonics = scroll.buttons["harmonic-picker"]
    reveal(harmonics, in: scroll)
    harmonics.tap()
    let resonance = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Jovian resonance")
    ).firstMatch
    requireHittable(resonance)
    resonance.tap()

    let channels = scroll.segmentedControls["channel-picker"]
    let frequency = scroll.sliders["Frequency, linear control"]
    for (channel, expected) in [("A", 0.4), ("B", 0.2), ("C", 0.1)] {
      reveal(channels, in: scroll)
      channels.buttons[channel].tap()
      reveal(frequency, in: scroll)
      XCTAssertEqual(
        numericValue(frequency), expected, accuracy: 0.001,
        "The Jovian preset fills channel \(channel) with its 4:2:1 frequency.")
    }

    let originalFrequency = frequency.value as? String ?? ""
    frequency.adjust(toNormalizedSliderPosition: 0.65)
    wait(
      NSPredicate(format: "value != %@", originalFrequency), on: frequency,
      message: "A harmonic remains a freely editable starting point")
    reveal(channels, in: scroll)
    channels.buttons["A"].tap()
    reveal(frequency, in: scroll)
    XCTAssertEqual(
      numericValue(frequency), 0.4, accuracy: 0.001,
      "Editing channel C after loading harmonics must leave channel A unchanged.")
    dismissMotionSheet(in: app)
    XCTAssertEqual(app.buttons["transport-play"].label, "Play")
  }

  @MainActor
  func testAccessibilityMotionResetControlsFit() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    openMotionSheet(in: app)
    for identifier in ["motion-reset-dials", "motion-reset-alignment"] {
      let button = app.buttons[identifier]
      requireHittable(button)
      XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
      XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
      XCTAssertGreaterThanOrEqual(button.frame.minY, app.frame.minY)
      XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
      button.tap()
    }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Orbitals — accessible Motion Control resets"
    attachment.lifetime = .keepAlways
    add(attachment)
    dismissMotionSheet(in: app)
    XCTAssertEqual(app.buttons["transport-play"].label, "Play")
  }

  @MainActor
  private func launchPausedApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    XCTAssertTrue(app.buttons["transport-play"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  private func openMotionSheet(in app: XCUIApplication) {
    let button = app.buttons["motion-controls-open"]
    requireHittable(button)
    button.tap()
    XCTAssertTrue(app.navigationBars["Motion control"].waitForExistence(timeout: 5))
  }

  @MainActor
  private func dismissMotionSheet(in app: XCUIApplication) {
    let done = app.buttons["Done"]
    requireHittable(done)
    done.tap()
    wait(
      NSPredicate(format: "exists == false"), on: app.navigationBars["Motion control"],
      message: "The motion sheet closes")
  }

  @MainActor
  private func numericValue(_ element: XCUIElement) -> Double {
    let value = element.value as? String ?? ""
    guard
      let number = value.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "-" }).first,
      let parsed = Double(number)
    else {
      XCTFail("Expected a numeric control value, received \(value)")
      return .nan
    }
    return parsed
  }

  @MainActor
  private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))
    for _ in 0..<12 {
      if element.exists, element.isHittable,
        scroll.frame.insetBy(dx: -2, dy: -2).contains(element.frame)
      {
        return
      }
      let towardBottom = !element.exists || element.frame.midY > scroll.frame.midY
      scrollGutter(scroll, towardBottom: towardBottom)
    }
    XCTFail("Could not reveal \(element) in its scroll view")
  }

  @MainActor
  private func scrollGutter(_ scroll: XCUIElement, towardBottom: Bool) {
    // A gutter drag cannot accidentally turn a knob or rotate the Metal canvas.
    let startY = towardBottom ? 0.78 : 0.30
    let endY = towardBottom ? 0.30 : 0.78
    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: startY))
      .press(
        forDuration: 0.05,
        thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: endY)))
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
