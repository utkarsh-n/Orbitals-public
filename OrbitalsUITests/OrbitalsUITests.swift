import XCTest

final class OrbitalsUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTransportSingleStepPlayAndPause() {
    let app = launchPausedApp()
    let play = app.buttons["transport-play"]
    requireHittable(play)
    XCTAssertEqual(play.label, "Play")
    XCTAssertTrue(clockLabel(in: app, time: "00:00.00").exists)

    let step = app.buttons["transport-step"]
    requireHittable(step)
    step.tap()
    XCTAssertTrue(clockLabel(in: app, time: "00:00.01").waitForExistence(timeout: 5))
    XCTAssertEqual(play.label, "Play", "One step must leave the simulation paused.")

    play.tap()
    wait(NSPredicate(format: "label == %@", "Pause"), on: play, message: "Play changes to Pause")
    play.tap()
    wait(NSPredicate(format: "label == %@", "Play"), on: play, message: "Pause changes to Play")
    XCTAssertFalse(app.staticTexts["Renderer unavailable"].exists)
  }

  @MainActor
  func testAccessibilityXXXLTransportFitsAndSteps() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing",
      "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    let play = app.buttons["transport-play"]
    let step = app.buttons["transport-step"]
    let actions = app.buttons["Experiment actions"]
    for control in [play, step, actions] {
      requireHittable(control)
      XCTAssertGreaterThanOrEqual(
        control.frame.minX, app.frame.minX,
        "Transport must fit within the leading screen edge at accessibility XXXL.")
      XCTAssertLessThanOrEqual(
        control.frame.maxX, app.frame.maxX,
        "Transport must fit within the trailing screen edge at accessibility XXXL.")
      XCTAssertGreaterThan(control.frame.width, 0)
    }
    XCTAssertEqual(play.label, "Play")
    step.tap()
    XCTAssertTrue(clockLabel(in: app, time: "00:00.01").waitForExistence(timeout: 5))
    XCTAssertEqual(play.label, "Play")

    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Orbitals — Accessibility XXXL transport"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testAllFiveViewsRotateAndRetconRemainsVisible() {
    let app = launchPausedApp()
    let dimensions = app.segmentedControls["dimension-picker"]
    requireHittable(dimensions.buttons["5D"])
    dimensions.buttons["5D"].tap()

    let selector = app.scrollViews["view-selector"]
    XCTAssertTrue(selector.waitForExistence(timeout: 5))
    let views = [
      ("spatial", "Spatial scope"),
      ("cylinder", "Time cylinder"),
      ("torus", "Time torus"),
      ("tracks", "Orbital tracks"),
      ("retcon", "Retcon torus"),
    ]
    for (identifier, title) in views {
      let button = app.buttons["view-\(identifier)"]
      reveal(button, in: selector, direction: .left, requireFullVisibility: false)
      // A clipped neighboring tab is an intentional, tappable scroll affordance.
      // Tap its visible center, then verify that selection centers the whole tab.
      let visibleTab = button.frame.intersection(selector.frame)
      button.coordinate(withNormalizedOffset: .zero)
        .withOffset(
          CGVector(dx: visibleTab.midX - button.frame.minX, dy: visibleTab.midY - button.frame.minY)
        )
        .tap()
      waitForFullVisibility(button, in: selector)

      let canvas = app.descendants(matching: .any).matching(identifier: "orbital-canvas").firstMatch
      requireHittable(canvas)
      wait(
        NSPredicate(format: "label == %@", "\(title), interactive projection"), on: canvas,
        message: "The selected view reaches the Metal canvas")
      let initialAttitude = canvas.value as? String ?? ""
      XCTAssertFalse(initialAttitude.isEmpty)

      // The middle of the canvas stays clear of both navigation and transport.
      let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.40))
      let finish = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.48))
      start.press(forDuration: 0.08, thenDragTo: finish)
      wait(
        NSPredicate(
          format: "exists == true AND value BEGINSWITH %@ AND value != %@", "Yaw ", initialAttitude),
        on: canvas, message: "Dragging rotates \(title)")
      XCTAssertFalse(app.staticTexts["Renderer unavailable"].exists)

      let embeddedSize = canvas.frame.size
      let embeddedCamera = canvas.value as? String ?? ""
      requireHittable(app.buttons["visualization-expand"])
      app.buttons["visualization-expand"].tap()
      let expanded = app.descendants(matching: .any).matching(
        identifier: "orbital-canvas-fullscreen"
      ).firstMatch
      requireHittable(expanded)
      wait(
        NSPredicate(format: "label CONTAINS %@", title), on: expanded,
        message: "The popout retains the selected \(title)")
      XCTAssertGreaterThan(
        expanded.frame.width, embeddedSize.width, "The popout gains usable canvas width.")
      XCTAssertGreaterThan(
        expanded.frame.height, embeddedSize.height, "The popout gains usable canvas height.")
      XCTAssertEqual(
        expanded.value as? String, embeddedCamera, "Opening full screen preserves the camera.")
      expanded.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.42))
        .press(
          forDuration: 0.08,
          thenDragTo: expanded.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.48)))
      wait(
        NSPredicate(format: "exists == true AND value != %@", embeddedCamera), on: expanded,
        message: "The full screen \(title) remains interactive")
      let expandedCamera = expanded.value as? String
      requireHittable(app.buttons["visualization-close"])
      app.buttons["visualization-close"].tap()
      wait(
        NSPredicate(format: "exists == false"), on: expanded, message: "The \(title) popout closes")
      requireHittable(canvas)
      XCTAssertEqual(
        canvas.value as? String, expandedCamera, "Closing full screen preserves camera changes.")
      XCTAssertEqual(app.buttons["transport-play"].label, "Play")
      XCTAssertTrue(
        clockLabel(in: app, time: "00:00.00").exists,
        "Opening, manipulating, and closing a view must preserve the paused clock.")
    }

    XCTAssertTrue(
      app.staticTexts[
        "Blue ghosts keep the original past. Solid traces rewrite it; dashed traces predict the future."
      ].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Orbitals — Retcon torus after camera drag"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testFullScreenPinchPanZoomControlsAndReset() {
    let app = launchPausedApp()
    requireHittable(app.buttons["visualization-expand"])
    app.buttons["visualization-expand"].tap()
    let canvas = app.descendants(matching: .any).matching(identifier: "orbital-canvas-fullscreen")
      .firstMatch
    requireHittable(canvas)
    let defaultCamera = cameraState(canvas)
    let initialValue = canvas.value as? String ?? ""

    // Exercise a real two-finger pinch, independent of the accessible buttons.
    canvas.pinch(withScale: 1.6, velocity: 1.0)
    wait(
      NSPredicate(format: "value != %@", initialValue), on: canvas,
      message: "A pinch changes the full screen camera")
    let pinched = cameraState(canvas)
    XCTAssertGreaterThan(pinched[2], defaultCamera[2], "Pinching outward increases zoom.")
    XCTAssertEqual(pinched[0], defaultCamera[0], "Pinch does not rotate yaw.")
    XCTAssertEqual(pinched[1], defaultCamera[1], "Pinch does not rotate tilt.")

    let zoomIn = app.buttons["camera-zoom-in"]
    let zoomOut = app.buttons["camera-zoom-out"]
    requireHittable(zoomIn)
    zoomIn.tap()
    let afterZoomIn = cameraState(canvas)
    XCTAssertGreaterThan(afterZoomIn[2], pinched[2], "The accessible zoom-in action works.")
    requireHittable(zoomOut)
    zoomOut.tap()
    let afterZoomOut = cameraState(canvas)
    XCTAssertLessThan(afterZoomOut[2], afterZoomIn[2], "The accessible zoom-out action works.")

    let panMode = app.descendants(matching: .any).matching(identifier: "camera-pan-mode").firstMatch
    requireHittable(panMode)
    panMode.tap()
    let beforePan = cameraState(canvas)
    let beforePanValue = canvas.value as? String ?? ""
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.43))
      .press(
        forDuration: 0.08,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.54)))
    wait(
      NSPredicate(format: "value != %@", beforePanValue), on: canvas,
      message: "Move mode pans the full screen view")
    let afterPan = cameraState(canvas)
    XCTAssertEqual(afterPan[0], beforePan[0], "Panning preserves yaw.")
    XCTAssertEqual(afterPan[1], beforePan[1], "Panning preserves tilt.")
    XCTAssertEqual(afterPan[2], beforePan[2], "One-finger panning preserves zoom.")
    XCTAssertTrue(
      afterPan[3] != beforePan[3] || afterPan[4] != beforePan[4], "The drag changes the pan offset."
    )

    canvas.doubleTap()
    wait(
      NSPredicate(format: "value == %@", initialValue), on: canvas,
      message: "Double tap resets yaw, tilt, zoom, and pan")
    XCTAssertEqual(cameraState(canvas), defaultCamera)
    zoomIn.tap()
    XCTAssertGreaterThan(cameraState(canvas)[2], defaultCamera[2])
    requireHittable(app.buttons["fullscreen-reset-camera"])
    app.buttons["fullscreen-reset-camera"].tap()
    wait(
      NSPredicate(format: "value == %@", initialValue), on: canvas,
      message: "The accessible reset action restores the camera")

    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Orbitals — Full screen CMY projection and gesture controls"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    app.buttons["visualization-close"].tap()
    wait(
      NSPredicate(format: "exists == false"), on: canvas,
      message: "Full screen closes after gesture adjustments")
    XCTAssertEqual(app.buttons["transport-play"].label, "Play")
    XCTAssertTrue(clockLabel(in: app, time: "00:00.00").exists)
    app.buttons["transport-step"].tap()
    XCTAssertTrue(
      clockLabel(in: app, time: "00:00.01").waitForExistence(timeout: 5),
      "One clock step remains 1/60 second after using the popout.")
  }

  @MainActor
  func testFullScreenLandscapeKeepsCameraAndControlsVisible() {
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    let app = launchPausedApp()
    let dimensions = app.segmentedControls["dimension-picker"]
    requireHittable(dimensions.buttons["5D"])
    dimensions.buttons["5D"].tap()
    requireHittable(app.buttons["visualization-expand"])
    app.buttons["visualization-expand"].tap()
    let canvas = app.descendants(matching: .any).matching(identifier: "orbital-canvas-fullscreen").firstMatch
    requireHittable(canvas)
    let defaultCamera = canvas.value as? String ?? ""
    requireHittable(app.buttons["camera-zoom-in"])
    app.buttons["camera-zoom-in"].tap()
    wait(NSPredicate(format: "value != %@", defaultCamera), on: canvas, message: "Portrait zoom changes before orientation changes")
    let portraitCamera = canvas.value as? String

    XCUIDevice.shared.orientation = .landscapeLeft
    wait(
      NSPredicate { _, _ in
        app.frame.width > app.frame.height && canvas.frame.width > canvas.frame.height
      },
      on: canvas, message: "The full screen canvas adopts the landscape viewport")
    XCTAssertEqual(canvas.value as? String, portraitCamera, "Rotation preserves yaw, tilt, zoom, and pan.")

    let controls = [
      app.buttons["Visualization"],
      app.buttons["visualization-close"],
      app.buttons["fullscreen-play"],
      app.buttons["camera-pan-mode"],
      app.buttons["camera-zoom-out"],
      app.buttons["camera-zoom-in"],
      app.buttons["fullscreen-reset-camera"],
    ]
    for control in controls {
      requireHittable(control)
      XCTAssertTrue(
        app.frame.insetBy(dx: -1, dy: -1).contains(control.frame),
        "\(control.identifier.isEmpty ? control.label : control.identifier) must remain fully inside the landscape display.")
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Orbitals — Landscape fullscreen controls"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    app.buttons["fullscreen-reset-camera"].tap()
    wait(NSPredicate(format: "value == %@", defaultCamera), on: canvas, message: "Camera reset works in landscape")
    app.buttons["visualization-close"].tap()
    wait(NSPredicate(format: "exists == false"), on: canvas, message: "The landscape popout closes")
    requireHittable(app.buttons["transport-play"])
    XCTAssertEqual(app.buttons["transport-play"].label, "Play")
    XCTAssertTrue(clockLabel(in: app, time: "00:00.00").exists)
  }

  @MainActor
  func testFlightControlsExposeAndAdjustMotionAndGeometry() {
    let app = launchPausedApp()
    requireHittable(app.buttons["All controls"])
    app.buttons["All controls"].tap()
    XCTAssertTrue(app.navigationBars["Flight controls"].waitForExistence(timeout: 5))
    let scroll = app.scrollViews["controls-scroll"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))

    let speed = scroll.sliders["Speed, linear control"]
    reveal(speed, in: scroll, direction: .up)
    let originalSpeed = speed.value as? String ?? ""
    speed.adjust(toNormalizedSliderPosition: 0.72)
    wait(
      NSPredicate(format: "value != %@", originalSpeed), on: speed,
      message: "The native speed slider changes its numeric readout")

    let radius = scroll.sliders["Radius"]
    reveal(radius, in: scroll, direction: .up)
    let originalRadius = radius.value as? String ?? ""
    radius.adjust(toNormalizedSliderPosition: 0.8)
    wait(
      NSPredicate(format: "value != %@", originalRadius), on: radius,
      message: "The radius slider changes geometry")

    requireHittable(app.buttons["Done"])
    app.buttons["Done"].tap()
    wait(
      NSPredicate(format: "exists == false"), on: app.navigationBars["Flight controls"],
      message: "The controls sheet closes")
    requireHittable(app.buttons["transport-play"])
    XCTAssertEqual(
      app.buttons["transport-play"].label, "Play",
      "Editing settings must not start a paused simulation.")
  }

  @MainActor
  func testFieldNotesExplainProjectionAndDismiss() {
    let app = launchPausedApp()
    requireHittable(app.buttons["Field notes"])
    app.buttons["Field notes"].tap()
    XCTAssertTrue(app.navigationBars["Field notes"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Orbitals explores motion, projection and time."].exists)
    let scroll = app.scrollViews["field-notes-scroll"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))
    let projection = scroll.staticTexts.matching(
      NSPredicate(
        format: "label == %@",
        "5D means four spatial coordinates plus simulation time. Every view is a projection, not a literal picture of five-dimensional space."
      )
    ).firstMatch
    reveal(projection, in: scroll, direction: .up)
    XCTAssertTrue(projection.isHittable)
    app.buttons["Done"].tap()
    wait(
      NSPredicate(format: "exists == false"), on: app.navigationBars["Field notes"],
      message: "Field notes close")
    requireHittable(app.buttons["transport-play"])
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
  private func clockLabel(in app: XCUIApplication, time: String) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Simulation paused, \(time)")
    ).firstMatch
  }

  @MainActor
  private func cameraState(
    _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) -> [Double] {
    let value = element.value as? String ?? ""
    let parts = value.components(separatedBy: ", ")
    let numbers = parts.compactMap { part in
      part.split(separator: " ").compactMap { Double($0) }.first
    }
    guard parts.count == 5, numbers.count == 5 else {
      XCTFail(
        "Expected yaw, tilt, zoom, pan X, pan Y in canvas value; received: \(value)", file: file,
        line: line)
      return Array(repeating: .nan, count: 5)
    }
    return numbers
  }

  @MainActor
  private func requireHittable(
    _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      element.waitForExistence(timeout: 5), "Missing element: \(element)", file: file, line: line)
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == true"), object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
      "Element is not hittable: \(element)", file: file, line: line)
  }

  private enum ScrollDirection { case up, left }

  @MainActor
  private func reveal(
    _ element: XCUIElement, in scroll: XCUIElement, direction: ScrollDirection,
    requireFullVisibility: Bool = true,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(scroll.waitForExistence(timeout: 5), file: file, line: line)
    for _ in 0..<8 {
      if element.exists && element.isHittable {
        let visible = element.frame.intersection(scroll.frame)
        if visible.width >= min(element.frame.width, scroll.frame.width) - 2,
          visible.height >= min(element.frame.height, scroll.frame.height) - 2
        {
          return
        }
        if !requireFullVisibility,
          visible.width >= min(44, element.frame.width),
          visible.height >= min(44, element.frame.height)
        {
          return
        }
      }
      switch direction {
      case .left:
        // Move toward the target, including recovering from overshoot.
        // Short drags avoid skipping a neighboring tab on narrow phones.
        let viewport = scroll.frame
        let target = element.exists ? element.frame : .zero
        let needsRightwardDrag = target.width > 0 && target.minX < viewport.minX + 2
        let hiddenWidth =
          needsRightwardDrag
          ? viewport.minX + 6 - target.minX
          : target.maxX - viewport.maxX + 6
        let distance =
          target.width > 0
          ? min(0.35, max(0.1, hiddenWidth / max(1, viewport.width)))
          : 0.35
        let startX = needsRightwardDrag ? 0.3 : 0.7
        let endX = startX + (needsRightwardDrag ? distance : -distance)
        scroll.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
          .press(
            forDuration: 0.05,
            thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5)))
      case .up:
        // Scroll at the outer gutter so a knob never steals the gesture.
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.78))
          .press(
            forDuration: 0.05,
            thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.34)))
      }
    }
    XCTFail("Could not reveal \(element) in its scroll view", file: file, line: line)
  }

  @MainActor
  private func waitForFullVisibility(
    _ element: XCUIElement, in scroll: XCUIElement,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let centered = NSPredicate { _, _ in
      guard element.exists, element.isHittable else { return false }
      let bounds = element.frame
      let viewport = scroll.frame
      let visible = bounds.intersection(viewport)
      return visible.width >= min(bounds.width, viewport.width) - 2
        && visible.height >= min(bounds.height, viewport.height) - 2
    }
    wait(
      centered, on: element, message: "Selecting a view scrolls its whole tab into view",
      file: file, line: line)
  }

  @MainActor
  private func wait(
    _ predicate: NSPredicate, on element: XCUIElement, message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 5), .completed, message, file: file, line: line)
  }
}
