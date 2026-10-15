import SwiftUI

struct ControlsView: View {
  @Bindable var model: OrbitModel
  var embedded: Bool
  var body: some View {
    VStack(spacing: 18) {
      if !embedded { MotionControls(model: model) }
      InstrumentPanel(title: "Geometry", number: "02") {
        GlassSlider(
          title: "Circle → sphere",
          value: Binding(
            get: { model.settings.morph },
            set: {
              model.settings.morph = $0
              model.dimension = $0 < 0.001 ? 2 : 3
            }), range: 0...1, step: 0.01, precision: 2
        )
        .disabled(model.settings.fourD)
        GlassSlider(
          title: "Radius", value: setting(\.radius), range: 0.5...3, step: 0.01, unit: "u")
        GlassToggle(
          title: "Fourth dimension · w",
          isOn: Binding(get: { model.settings.fourD }, set: { model.setDimension($0 ? 4 : 3) }),
          symbol: "cube.transparent")
        if model.settings.fourD {
          GlassSlider(
            title: "XW rotation", value: setting(\.xw), range: -180...180, step: 1, unit: "°",
            precision: 0)
          GlassSlider(
            title: "YW rotation", value: setting(\.yw), range: -180...180, step: 1, unit: "°",
            precision: 0)
          GlassSlider(
            title: "ZW rotation", value: setting(\.zw), range: -180...180, step: 1, unit: "°",
            precision: 0)
        }
        Text(
          model.settings.fourD
            ? "The fourth spatial coordinate is shown through perspective projection."
            : "The latitude opens smoothly from an equatorial circle to a sphere."
        )
        .font(.caption).foregroundStyle(OrbitTheme.muted)
      }
      InstrumentPanel(title: "Display & attitude", number: "03") {
        GlassToggle(
          title: "Mesh & motion paths", isOn: setting(\.mesh), symbol: "circle.hexagongrid")
        GlassToggle(
          title: "Coordinate axes", isOn: setting(\.axes),
          symbol: "arrow.up.and.down.and.arrow.left.and.right")
        GlassToggle(title: "Trails", isOn: setting(\.trails), symbol: "scribble.variable")
        GlassToggle(
          title: "Connecting lines", isOn: setting(\.connections),
          symbol: "point.3.connected.trianglepath.dotted")
        GlassSlider(
          title: "Persistence", value: setting(\.persistence), range: 0.5...12, step: 0.1,
          unit: "s", precision: 1)
        GlassSlider(
          title: "Phosphor glow", value: setting(\.glow), range: 0...1, step: 0.01, precision: 2,
          color: OrbitTheme.phosphor)
        Divider()
        Text("\(model.selectedView.title) camera").font(.subheadline.weight(.medium))
        GlassSlider(
          title: "Yaw",
          value: Binding(
            get: { model.camera.yaw }, set: { model.setCamera(yaw: $0, pitch: model.camera.pitch) }),
          range: -180...180, step: 1, unit: "°", precision: 0)
        GlassSlider(
          title: "Tilt",
          value: Binding(
            get: { model.camera.pitch }, set: { model.setCamera(yaw: model.camera.yaw, pitch: $0) }),
          range: -85...85, step: 1, unit: "°", precision: 0)
        GlassSlider(
          title: "Zoom",
          value: Binding(get: { model.camera.zoom }, set: { model.setViewport(zoom: $0) }),
          range: 0.25...6, step: 0.05, unit: "×", precision: 2)
        ActionButton(title: "Reset view", symbol: "viewfinder") { model.resetCamera() }
      }
      InstrumentPanel(title: "Experiment presets", number: "04") {
        Menu {
          ForEach(
            ["Circle study", "Spherical orbits", "Lissajous study", "Hyperspace"], id: \.self
          ) { name in
            Button(name) {
              OrbitalHaptics.shared.success()
              model.applyPreset(name)
            }
          }
        } label: {
          HStack {
            Text(model.preset)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
          }.padding(.vertical, 10)
        }.buttonStyle(.glass).tint(OrbitTheme.amber)
          .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
          .accessibilityLabel("Experiment preset, \(model.preset)")
        Text(
          "Load a starting point, then make it your own. Presets restart the simulation and recorded history."
        ).font(.caption).foregroundStyle(OrbitTheme.muted)
      }
      InstrumentPanel(title: "Physical feedback", number: "05") {
        GlassToggle(title: "Haptics", isOn: $model.hapticsEnabled, symbol: "waveform.path")
        GlassSlider(
          title: "Intensity", value: $model.hapticStrength, range: 0.2...1, step: 0.05,
          precision: 2, color: OrbitTheme.phosphor
        ).disabled(!model.hapticsEnabled)
        ActionButton(title: "Feel a detent", symbol: "hand.tap") {
          OrbitalHaptics.shared.boundary()
        }
        Text(
          "Distinct taps, dial detents and end stops. Haptics require supported hardware and follow device settings."
        ).font(.caption).foregroundStyle(OrbitTheme.muted)
      }
    }
  }
  private func setting<T>(_ key: WritableKeyPath<OrbitalSettings, T>) -> Binding<T> {
    Binding(get: { model.settings[keyPath: key] }, set: { model.settings[keyPath: key] = $0 })
  }
}

struct TimelineInspector: View {
  @Bindable var model: OrbitModel
  var body: some View {
    InstrumentPanel(title: "Time projection", number: "T") {
      HStack(spacing: 14) {
        legend("Recorded", color: OrbitTheme.phosphor, symbol: "line.diagonal")
        legend(
          "Now", color: model.selectedView == .cylinder ? .white : OrbitTheme.amber,
          symbol: "circle")
        legend("Predicted", color: OrbitTheme.cyan, symbol: "ellipsis")
      }.font(.caption)
      GlassSlider(
        title: "Past / future window", value: $model.horizon, range: 2...20, step: 1, unit: "s",
        precision: 0)
      if model.selectedView == .cylinder {
        Picker("Coordinate plane", selection: $model.plane) {
          ForEach(CoordinatePlane.allCases) { Text($0.rawValue).tag($0) }
        }.onChange(of: model.plane) { _, _ in OrbitalHaptics.shared.selection() }
      }
      GlassSlider(
        title: "Inspect time", value: $model.inspectionOffset,
        range: -model.horizon...model.horizon, step: 0.05, unit: "s")
      HStack {
        Readout(
          title: model.inspectionOffset < 0
            ? "Recorded past" : model.inspectionOffset > 0 ? "Conditional future" : "Present",
          value: String(format: "t = %.2f s", model.inspectedTime))
        Spacer()
        ActionButton(title: "Now", symbol: "scope") { model.inspectionOffset = 0 }
      }
      CoordinatesTable(points: model.inspectedPoints, fourD: true)
      Text(
        model.inspectedPoints == nil
          ? "No recording exists at this time. The empty values preserve that gap."
          : "Forecasts use the current controls. Recorded coordinates stay unchanged."
      )
      .font(.caption).foregroundStyle(OrbitTheme.muted).frame(minHeight: 36, alignment: .topLeading)
      HStack {
        Text(String(format: "%.1f s recorded", model.archiveSeconds)).font(
          .system(.caption, design: .monospaced)
        ).foregroundStyle(OrbitTheme.muted)
        Spacer()
        ActionButton(title: "Clear history", symbol: "eraser") { model.clearHistory() }
      }
    }
  }
  private func legend(_ text: String, color: Color, symbol: String) -> some View {
    Label(text, systemImage: symbol).foregroundStyle(color)
  }
}

struct LoopControls: View {
  @Bindable var model: OrbitModel
  var body: some View {
    InstrumentPanel(title: "Simulated loop", number: "04") {
      GlassToggle(title: "Simulated loop", isOn: $model.loopEnabled, symbol: "repeat")
      Text(
        "Paths hold still while the nodes race. Shape controls deform the tracks; frequency and speed set the pace."
      )
      .font(.caption).foregroundStyle(OrbitTheme.muted)
      Menu {
        ForEach(LoopProgram.presets.keys.sorted(), id: \.self) { name in
          Button(name) {
            OrbitalHaptics.shared.selection()
            model.applyLoopPreset(name)
          }
        }
      } label: {
        Label(model.loopPreset, systemImage: "waveform.path")
      }.buttonStyle(.glass)
        .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
      GlassSlider(
        title: "Duration", value: rate(\.duration), range: 8...60, step: 1, unit: "s", precision: 0)
      GlassSlider(title: "Base laps", value: rate(\.laps), range: 1...8, step: 1, precision: 0)
      GlassSlider(
        title: "Pace cycles", value: rate(\.pace), range: 0...6, step: 1, unit: "/ loop",
        precision: 0)
      GlassSlider(
        title: "Excitation cycles", value: rate(\.excitation), range: 0...6, step: 1,
        unit: "/ loop", precision: 0)
      GlassSlider(
        title: "Radius cycles", value: rate(\.radius), range: 0...6, step: 1, unit: "/ loop",
        precision: 0)
      GlassSlider(
        title: "Rotation cycles", value: rate(\.rotation), range: 0...6, step: 1, unit: "/ loop",
        precision: 0)
      GlassSlider(
        title: "Modulation depth", value: rate(\.depth), range: 0...1, step: 0.01, precision: 2)
      ProgressView(value: model.loopEnabled ? model.loopProgress : 0).tint(OrbitTheme.phosphor)
      HStack {
        Readout(
          title: "Loop phase",
          value: String(
            format: "%.1f / %.0f s",
            model.loopEnabled ? model.loopProgress * model.loopProgram.duration : 0,
            model.loopProgram.duration))
        Spacer()
        ActionButton(title: "Restart", symbol: "arrow.counterclockwise") { model.restartLoop() }
      }
      Text(
        "Rates are whole cycles per loop; zero holds a parameter. This program affects the track view only. Global play, pause and step control its clock."
      ).font(.caption).foregroundStyle(OrbitTheme.muted)
    }
  }
  private func rate(_ key: WritableKeyPath<LoopProgram, Double>) -> Binding<Double> {
    Binding(
      get: { model.loopProgram[keyPath: key] },
      set: {
        model.loopPreset = "Custom sequence"
        model.loopProgram[keyPath: key] = $0
      })
  }
}

struct RetconControls: View {
  @Bindable var model: OrbitModel
  var body: some View {
    InstrumentPanel(title: "Rewrite time. Retain its echo.", number: "05") {
      Text(
        "The current equations rewrite the past and future in this branch. Original recordings remain visible as ghosts."
      )
      .font(.subheadline).foregroundStyle(OrbitTheme.muted)
      GlassSlider(
        title: "Rewrite phase", value: $model.retconPhase, range: -180...180, step: 1, unit: "°",
        precision: 0, color: OrbitTheme.cyan)
      GlassSlider(
        title: "Ghost strength", value: $model.ghostStrength, range: 0.2...0.8, step: 0.05,
        precision: 2, color: OrbitTheme.cyan)
      ActionButton(title: "Reset phase", symbol: "arrow.counterclockwise", tint: OrbitTheme.cyan) {
        model.retconPhase = 0
      }
      GlassSlider(
        title: "Past / future window", value: $model.horizon, range: 2...20, step: 1, unit: "s",
        precision: 0, color: OrbitTheme.cyan)
      GlassSlider(
        title: "Compare a moment", value: $model.retconOffset,
        range: -model.horizon...model.horizon, step: 0.05, unit: "s", color: OrbitTheme.cyan)
      Readout(
        title: model.retconOffset < 0
          ? "Rewritten past" : model.retconOffset > 0 ? "Rewritten future" : "Rewritten present",
        value: String(format: "t = %.2f s", model.retconTime), color: OrbitTheme.cyan)
      ForEach(0..<3, id: \.self) { i in
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("CHANNEL \(["A","B","C"][i])").foregroundStyle(OrbitTheme.channels[i])
            Spacer()
            Text(model.retconDeltas.map { String(format: "Δ %.3f u", $0[i]) } ?? "Δ — u")
              .foregroundStyle(OrbitTheme.cyan)
          }.font(.system(.caption, design: .monospaced))
          VStack(alignment: .leading, spacing: 4) {
            Text("ORIGINAL").foregroundStyle(OrbitTheme.muted)
            Text(coordinates(model.retconOriginal?[i])).foregroundStyle(
              OrbitTheme.cyan.opacity(0.7))
            Text("REWRITTEN").foregroundStyle(OrbitTheme.muted).padding(.top, 4)
            Text(
              coordinates(
                model.retconRewritten.indices.contains(i) ? model.retconRewritten[i] : nil)
            ).foregroundStyle(OrbitTheme.channels[i])
          }.font(.system(.caption, design: .monospaced)).monospacedDigit()
        }.padding(.vertical, 8)
        if i < 2 { Divider() }
      }
      Text(
        "Coordinates: x / y / z / w. Δ compares the same recorded instant in 4D. Before recording began, the past is computed. The rear torus closure is a visual blend."
      )
      .font(.caption).foregroundStyle(OrbitTheme.muted)
    }
  }
  private func coordinates(_ p: Vec4?) -> String {
    guard let p else { return "— / — / — / —" }
    return (0..<4).map { String(format: "%+.2f", p[$0]) }.joined(separator: " / ")
  }
}
