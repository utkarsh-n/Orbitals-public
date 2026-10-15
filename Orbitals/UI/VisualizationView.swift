import SwiftUI

struct VisualizationPanel: View {
  @Bindable var model: OrbitModel
  let width: CGFloat
  let isRendering: Bool
  var onExpand: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.selectedView.title.uppercased()).tracking(1.8)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
          Text(model.selectedView.subtitle).font(.caption).foregroundStyle(OrbitTheme.muted)
        }
        Spacer(minLength: 0)
        Button {
          OrbitalHaptics.shared.tap()
          model.resetCamera()
        } label: {
          Label("Align", systemImage: "viewfinder")
        }
        .buttonStyle(.glass).controlSize(.large)
        .accessibilityLabel("Reset camera")
        Button {
          OrbitalHaptics.shared.tap()
          onExpand()
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.glass).controlSize(.large)
        .accessibilityLabel("Expand visualization")
        .accessibilityHint("Open this visualization full screen with zoom and move controls.")
        .accessibilityIdentifier("visualization-expand")
      }
      Group {
        if isRendering {
          OrbitalCanvas(model: model)
        } else {
          // The full-screen canvas owns rendering until it is dismissed.
          OrbitTheme.background.accessibilityHidden(true)
        }
      }
      .frame(height: max(300, min(width * 0.91, 530)))
      .clipShape(.rect(cornerRadius: 20))
      .overlay {
        RoundedRectangle(cornerRadius: 20)
          .strokeBorder(OrbitTheme.phosphor.opacity(0.2))
          .allowsHitTesting(false)
      }
      HStack(spacing: 6) {
        ChannelLegend()
        Spacer(minLength: 0)
        Text("\(Int(model.camera.zoom * 100))% · YAW \(Int(model.camera.yaw))°")
          .foregroundStyle(OrbitTheme.muted)
      }.font(.system(.caption2, design: .monospaced)).monospacedDigit()
      if model.selectedView == .spatial && model.settings.mesh {
        Text("Dashed paths show the current motion. Bright trails show recorded movement.")
          .font(.caption).foregroundStyle(OrbitTheme.muted)
      }
      if model.selectedView == .retcon {
        Text(
          "Blue ghosts keep the original past. Solid traces rewrite it; dashed traces predict the future."
        )
        .font(.caption).foregroundStyle(OrbitTheme.muted)
      }
    }
    .padding(16)
    .background(OrbitTheme.panel, in: .rect(cornerRadius: 28))
  }
}

/// Shared by the dashboard and full-screen presentation. Camera transforms live
/// in the model, so resizing or moving between presentations never resets them.
struct OrbitalCanvas: View {
  @Bindable var model: OrbitModel
  var panWithOneFinger = false
  var fullScreen = false

  var body: some View {
    ZStack {
      OrbitMetalView(
        source: model, redrawKey: model.redrawKey, running: model.isAnimating,
        onError: { model.renderError = $0 }
      ).accessibilityHidden(true)
      if !fullScreen { annotations }
      OrbitCanvasGestures(model: model, panWithOneFinger: panWithOneFinger)
        .accessibilityHidden(true)
      if let error = model.renderError {
        ContentUnavailableView(
          "Renderer unavailable", systemImage: "exclamationmark.triangle", description: Text(error)
        )
        .padding()
      }
    }
    .background(.black)
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(model.selectedView.title), interactive projection")
    .accessibilityValue(cameraDescription)
    .accessibilityHint(
      panWithOneFinger
        ? "Drag to move. Pinch to zoom. Double tap resets the view."
        : "One finger rotates. Two fingers move. Pinch to zoom. Double tap resets the view."
    )
    .accessibilityAdjustableAction { direction in
      turn(direction == .increment ? 5 : -5, 0)
    }
    .accessibilityAction(named: "Zoom in") { zoom(1.25) }
    .accessibilityAction(named: "Zoom out") { zoom(0.8) }
    .accessibilityAction(named: "Move left") { move(-0.1, 0) }
    .accessibilityAction(named: "Move right") { move(0.1, 0) }
    .accessibilityAction(named: "Move up") { move(0, -0.1) }
    .accessibilityAction(named: "Move down") { move(0, 0.1) }
    .accessibilityAction(named: "Reset camera") { reset() }
    .accessibilityIdentifier(fullScreen ? "orbital-canvas-fullscreen" : "orbital-canvas")
    .focusable()
    .onKeyPress(.leftArrow) {
      turn(-5, 0)
      return .handled
    }
    .onKeyPress(.rightArrow) {
      turn(5, 0)
      return .handled
    }
    .onKeyPress(.upArrow) {
      turn(0, 5)
      return .handled
    }
    .onKeyPress(.downArrow) {
      turn(0, -5)
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in
      zoom(1.25)
      return .handled
    }
    .onKeyPress(characters: CharacterSet(charactersIn: "-")) { _ in
      zoom(0.8)
      return .handled
    }
  }

  private var annotations: some View {
    VStack {
      HStack {
        Text(model.selectedView == .retcon ? "ORIGINAL PAST RETAINED" : projectionLabel)
        Spacer(minLength: 5)
        Text(revisionLabel)
      }
      .font(.system(size: 9, weight: .medium, design: .monospaced))
      .foregroundStyle(annotationColor)
      Spacer()
      Text("DRAG TO ROTATE · PINCH TO ZOOM")
        .font(.system(size: 9, design: .monospaced)).tracking(0.6)
        .foregroundStyle(OrbitTheme.muted)
    }.padding(14).allowsHitTesting(false)
  }
  private var revisionLabel: String {
    model.selectedView == .retcon ? String(format: "REV %03d", model.retconRevision) : "METAL"
  }
  private var annotationColor: Color {
    model.selectedView == .retcon ? OrbitTheme.cyan : OrbitTheme.phosphor.opacity(0.8)
  }
  private var projectionLabel: String {
    model.dimension >= 4 ? "4D → 3D → 2D" : model.dimension == 2 ? "CIRCLE" : "SPHERE"
  }
  private var cameraDescription: String {
    "Yaw \(Int(model.camera.yaw)) degrees, tilt \(Int(model.camera.pitch)) degrees, zoom \(Int(model.camera.zoom * 100)) percent, pan X \(Int(model.camera.panX * 100)) percent, pan Y \(Int(model.camera.panY * 100)) percent"
  }
  private func turn(_ yaw: Double, _ pitch: Double) {
    OrbitalHaptics.shared.selection()
    model.setCamera(yaw: model.camera.yaw + yaw, pitch: model.camera.pitch + pitch)
  }
  private func zoom(_ factor: Double) {
    OrbitalHaptics.shared.selection()
    model.zoomCamera(by: factor)
  }
  private func move(_ x: Double, _ y: Double) {
    OrbitalHaptics.shared.selection()
    model.panCamera(dx: x, dy: y)
  }
  private func reset() {
    OrbitalHaptics.shared.tap()
    model.resetCamera()
  }
}

struct FullScreenVisualization: View {
  @Bindable var model: OrbitModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var panWithOneFinger = false
  @State private var sheet: DashboardSheet?
  @State private var showingAR = false

  var body: some View {
    ZStack {
      if showingAR {
        OrbitTheme.background.ignoresSafeArea().accessibilityHidden(true)
      } else {
        OrbitalCanvas(model: model, panWithOneFinger: panWithOneFinger, fullScreen: true)
          .ignoresSafeArea()
      }
      VStack(spacing: 0) {
        header
        Spacer(minLength: 0)
        controls
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .background(OrbitTheme.background)
    .statusBarHidden()
    .fullScreenCover(isPresented: $showingAR, onDismiss: { model.invalidate() }) {
      OrbitARScreen(model: model)
    }
    .sheet(item: $sheet) { destination in
      InstrumentControlSheet(model: model, destination: destination)
    }
    .onKeyPress(.escape) {
      close()
      return .handled
    }
    .onKeyPress(.space) {
      OrbitalHaptics.shared.tap()
      model.running.toggle()
      return .handled
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Button {
        OrbitalHaptics.shared.tap()
        sheet = .motion
      } label: {
        Image(systemName: "dial.medium")
      }
      .buttonStyle(.glass).controlSize(.large)
      .accessibilityLabel("Motion control")
      .accessibilityIdentifier("fullscreen-motion-controls-open")
      if model.dimension == 5 {
        Menu {
          ForEach(OrbitalViewKind.allCases) { kind in
            Button {
              OrbitalHaptics.shared.selection()
              model.chooseView(kind)
            } label: {
              Label(kind.title, systemImage: model.selectedView == kind ? "checkmark" : kind.symbol)
            }
          }
        } label: {
          Label(model.selectedView.title, systemImage: "chevron.down")
            .font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .buttonStyle(.glass).controlSize(.large)
        .accessibilityLabel("Visualization")
        .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
      } else {
        Text(model.selectedView.title).font(.headline)
          .padding(.horizontal, 16).padding(.vertical, 12)
          .glassEffect(.regular, in: .capsule)
      }
      Spacer(minLength: 0)
      Button {
        OrbitalHaptics.shared.tap()
        showingAR = true
      } label: {
        Label("AR", systemImage: "arkit").font(.subheadline.weight(.semibold))
      }
      .buttonStyle(.glass).controlSize(.large)
      .accessibilityLabel("View in AR")
      .accessibilityHint("Place this visualization on a surface using your camera.")
      .accessibilityIdentifier("visualization-ar")
      Button(action: close) {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
      }.buttonStyle(.glass).controlSize(.large)
        .accessibilityLabel("Close full screen")
        .accessibilityIdentifier("visualization-close")
    }
  }

  private var controls: some View {
    VStack(spacing: 12) {
      if verticalSizeClass != .compact {
        HStack(spacing: 10) {
          ChannelLegend()
          Spacer(minLength: 0)
          Text("\(Int(model.camera.zoom * 100))%")
            .monospacedDigit().accessibilityLabel("Zoom \(Int(model.camera.zoom * 100)) percent")
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(OrbitTheme.background.opacity(0.82), in: .capsule)
        Text(
          panWithOneFinger
            ? "Drag to move · Pinch to zoom · Double tap to reset"
            : "Drag to rotate · Two fingers to move · Pinch to zoom"
        )
        .font(.caption).foregroundStyle(OrbitTheme.muted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(OrbitTheme.background.opacity(0.82), in: .capsule)
      }
      GlassEffectContainer(spacing: 10) {
        HStack(spacing: 10) {
          cameraButton(
            model.running ? "Pause" : "Play", symbol: model.running ? "pause.fill" : "play.fill",
            id: "fullscreen-play"
          ) {
            model.running.toggle()
          }
          cameraButton(
            "Move visualization", symbol: panWithOneFinger ? "hand.draw.fill" : "hand.draw",
            id: "camera-pan-mode"
          ) {
            panWithOneFinger.toggle()
          }
          .tint(panWithOneFinger ? OrbitTheme.yellow : OrbitTheme.phosphor)
          .accessibilityValue(panWithOneFinger ? "On" : "Off")
          .accessibilityAddTraits(panWithOneFinger ? .isSelected : [])
          cameraButton("Zoom out", symbol: "minus.magnifyingglass", id: "camera-zoom-out") {
            model.zoomCamera(by: 0.8)
          }
          cameraButton("Zoom in", symbol: "plus.magnifyingglass", id: "camera-zoom-in") {
            model.zoomCamera(by: 1.25)
          }
          cameraButton("Reset camera", symbol: "viewfinder", id: "fullscreen-reset-camera") {
            model.resetCamera()
          }
        }
      }
    }.frame(maxWidth: 470)
  }

  private func cameraButton(
    _ title: String, symbol: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button {
      OrbitalHaptics.shared.tap()
      action()
    } label: {
      Image(systemName: symbol).frame(minWidth: 18, minHeight: 22)
    }
    .buttonStyle(.glass).controlSize(.large)
    .accessibilityLabel(title).accessibilityIdentifier(id)
  }

  private func close() {
    OrbitalHaptics.shared.tap()
    dismiss()
  }
}

private struct ChannelLegend: View {
  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { index in
        Circle().fill(OrbitTheme.channels[index]).frame(width: 5, height: 5)
        Text(["A", "B", "C"][index]).foregroundStyle(OrbitTheme.channels[index])
          .accessibilityLabel(
            "Channel \(["A", "B", "C"][index]), \(OrbitTheme.channelNames[index])")
      }
    }
  }
}
