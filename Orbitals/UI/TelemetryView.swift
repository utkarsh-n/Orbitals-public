import SwiftUI

struct TelemetryPanel: View {
  let model: OrbitModel
  var body: some View {
    InstrumentPanel(title: "State vectors", number: "XYZW") {
      CoordinatesTable(points: model.points, fourD: model.settings.fourD)
      if model.points.count == 3 {
        HStack(alignment: .top) {
          ForEach(0..<3, id: \.self) { i in
            Readout(
              title: ["A ↔ B", "B ↔ C", "C ↔ A"][i],
              value: String(
                format: "%.3f u", OrbitalMath.distance(model.points[i], model.points[(i + 1) % 3]))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      Text(
        model.settings.fourD
          ? "Euclidean distances in 4D, measured before projection."
          : "Straight-line distances in space, not along the surface."
      )
      .font(.caption).foregroundStyle(OrbitTheme.muted)
    }
  }
}

struct CoordinatesTable: View {
  let points: [Vec4]?
  let fourD: Bool
  var body: some View {
    Grid(horizontalSpacing: 8, verticalSpacing: 13) {
      GridRow {
        Text("CH").foregroundStyle(OrbitTheme.muted)
        ForEach(0..<(fourD ? 4 : 3), id: \.self) { i in
          Text(["X", "Y", "Z", "W"][i]).foregroundStyle(OrbitTheme.muted).frame(
            maxWidth: .infinity, alignment: .trailing)
        }
      }
      ForEach(0..<3, id: \.self) { channel in
        GridRow {
          Text(["A", "B", "C"][channel]).foregroundStyle(OrbitTheme.channels[channel]).fontWeight(
            .bold)
          ForEach(0..<(fourD ? 4 : 3), id: \.self) { axis in
            Text(
              points.flatMap {
                $0.indices.contains(channel) ? String(format: "%+.2f", $0[channel][axis]) : nil
              } ?? "—"
            )
            .foregroundStyle(OrbitTheme.channels[channel]).monospacedDigit().frame(
              maxWidth: .infinity, alignment: .trailing
            )
            .accessibilityLabel(
              "Channel \(["A","B","C"][channel]), \(["X","Y","Z","W"][axis]) \(points.map { String(format:"%.3f",$0[channel][axis]) } ?? "not recorded")"
            )
          }
        }
      }
    }.font(.system(.caption, design: .monospaced))
  }
}

struct FieldNotesView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        InstrumentPanel(title: "A dimensional instrument", number: "01") {
          Text("Orbitals explores motion, projection and time.").font(.title3.weight(.medium))
          Text(
            "The morph control opens latitude continuously: a circle becomes a sphere. In 4D, a fourth coordinate w creates a hypersphere. Rotations in XW, YW and ZW preserve distances before perspective projection into 3D and onto the screen."
          )
          Text(
            "These are exact parametric motion studies, not a gravity or spacecraft navigation solver."
          )
        }
        InstrumentPanel(title: "Five ways to see", number: "02") {
          note(
            "Spatial projection",
            "Live positions, mesh, axes, connections and fading trails in cyan, magenta and yellow. Expand any view to full screen. Drag to rotate, use two fingers to move, pinch to zoom, or double tap to reset. Move mode lets one finger reposition the view."
          )
          note(
            "Time cylinder",
            "Recorded motion runs along one side of the present ring, with conditional predictions on the other. Choose any pair of spatial coordinates."
          )
          note(
            "Time torus",
            "Projected 4D cross-sections wrap time around a complete ring. A short rear blend joins the window ends visually; it does not make the equations periodic or change the archive."
          )
          note(
            "Orbital tracks",
            "Closed phase paths stay fixed as nodes ride them. The optional simulated loop repeats programmed pace, excitation, radius and rotation changes, isolated to this view."
          )
          note(
            "Retcon torus",
            "Current variables rewrite both the past and future in a separate branch. Blue ghosts preserve original recordings, and displacement readouts compare the same instant."
          )
        }
        InstrumentPanel(title: "Time & accuracy", number: "03") {
          Text(
            "5D means four spatial coordinates plus simulation time. Every view is a projection, not a literal picture of five-dimensional space."
          )
          Text(
            "The archive samples at 60 Hz and retains 30 simulation seconds. Parameter changes start a new segment, leaving discontinuities visible. Paused edits preserve recorded coordinates; one step advances exactly 1/60 second."
          )
          Text(
            "Future paths assume the current equations and controls. They are deterministic forecasts, not predictions of external events."
          )
        }
        InstrumentPanel(title: "Touch & efficiency", number: "04") {
          Text(
            "Turn a dial by dragging up or right. Sliders and VoiceOver adjustable actions offer precise alternatives. Every control has tactile feedback on supported iPhones; adjust its intensity in Flight controls."
          )
          Text(
            "Only the selected view renders. The clock and GPU pause in the background. Metal draws phosphor lines and halos; Low Power Mode reduces the frame rate. Experiments are saved locally, and all features work offline."
          )
          Link(
            "Apple: Liquid Glass materials",
            destination: URL(
              string: "https://developer.apple.com/design/human-interface-guidelines/materials")!)
          Link(
            "Apple: Playing haptics",
            destination: URL(
              string:
                "https://developer.apple.com/design/human-interface-guidelines/playing-haptics")!)
        }
        InstrumentPanel(title: "Reading the dials", number: "05") {
          note(
            "κ · Speed",
            "Kappa multiplies the base frequency. At 2×, the oscillator advances twice as fast.")
          note(
            "α · Amplitude",
            "Alpha is Orbitals’ normalized amplitude. It controls size, swing, latitude, tilt or pulse depth, depending on the motion. Flat 2D Orbit has no visible amplitude change."
          )
          note(
            "ν · Frequency",
            "Nu is the base oscillator frequency in hertz. A complete path can span several oscillator cycles."
          )
          note(
            "φ · Phase",
            "Phi offsets angles within the selected motion. Its effect can be position, orientation or harmonic alignment."
          )
          Text("Oscillator angle: q = 2πνκt")
            .font(.system(.subheadline, design: .monospaced)).foregroundStyle(OrbitTheme.phosphor)
          Text(
            "Dial colors identify parameters. Cyan, magenta and yellow continue to identify particle channels."
          )
        }
        InstrumentPanel(title: "Harmonic starters", number: "06") {
          Text(
            "Start with an exact relationship, then alter any dial. Each starter sets all three channels and begins a fresh recording while keeping your view and dimensions. These are scaled kinematic illustrations, not gravitational or coupled-oscillator simulations."
          )
          ForEach(HarmonicPreset.allCases) { preset in
            VStack(alignment: .leading, spacing: 5) {
              note("\(preset.title) · \(preset.ratioLabel)", preset.summary)
              Link(preset.sourceTitle, destination: preset.sourceURL).font(.caption)
            }
          }
          Text(
            "Reset dials restores the selected channel, or all linked channels. Reset alignment recenters all views without changing the simulation. Zero all phase offsets sets φ to 0°; different motion types or frequencies may still occupy different positions."
          )
        }
        InstrumentPanel(title: "Orbitals in your space", number: "07") {
          Text(
            "Open any visualization full screen and tap AR. Allow camera access, scan a textured table, floor or wall, then tap Place here. A world anchor keeps the projection in that place as you walk around it."
          )
          Text(
            "Pinch to resize and twist with two fingers to turn the shape. Move anchor lets you choose another surface; Scan a new space restarts tracking. The anchor lasts for the current AR session. Returning from a brief interruption attempts to recover it."
          )
          Text(
            "All five views use the same live equations and phosphor renderer. 4D remains a projection in AR, and 5D still adds simulation time. The transparent line art does not hide behind furniture or people. Camera frames and room maps are not saved."
          )
          Link(
            "Apple: Placing objects with ARKit",
            destination: URL(
              string:
                "https://developer.apple.com/documentation/arkit/placing-objects-and-handling-3d-interaction"
            )!)
        }
      }.font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding(16)
    }.accessibilityIdentifier("field-notes-scroll")
  }
  private func note(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).foregroundStyle(OrbitTheme.phosphor).fontWeight(.medium)
      Text(detail)
    }
  }
}
