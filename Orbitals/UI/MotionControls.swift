import SwiftUI

struct MotionControls: View {
  @Bindable var model: OrbitModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .caption) private var modeDescriptorHeight = 52.0
  var body: some View {
    InstrumentPanel(title: "Motion control", number: "01") {
      harmonicPicker
      HStack(spacing: 16) {
        Picker("Edit channel", selection: $model.selectedChannel) {
          Text("A").tag(0)
          Text("B").tag(1)
          Text("C").tag(2)
        }.pickerStyle(.segmented).accessibilityIdentifier("channel-picker")
          .onChange(of: model.selectedChannel) { _, _ in
            OrbitalHaptics.shared.selection()
          }
        GlassToggle(title: "Link", isOn: $model.linked, symbol: "link")
      }
      HStack(spacing: 7) {
        if model.linked {
          ForEach(0..<3, id: \.self) { index in
            Circle().fill(OrbitTheme.channels[index]).frame(width: 7, height: 7)
          }
          Text("Editing all three channels")
        } else {
          Circle().fill(OrbitTheme.channels[model.selectedChannel]).frame(width: 7, height: 7)
          Text(
            "Editing \(["A", "B", "C"][model.selectedChannel]) · \(OrbitTheme.channelNames[model.selectedChannel])"
          )
        }
        Spacer(minLength: 0)
      }
      .font(.system(.caption, design: .monospaced)).foregroundStyle(OrbitTheme.muted)
      motionSelector
      GlassEffectContainer(spacing: 16) {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
          spacing: 16
        ) {
          GlassKnob(
            title: "Speed", symbol: "κ", symbolName: "kappa",
            descriptor: "Multiplies the base frequency.",
            value: channel(\.speed), range: 0...3, step: 0.05, unit: "×",
            precision: 2, color: OrbitTheme.dialSpeed)
          GlassKnob(
            title: "Amplitude", symbol: "α", symbolName: "alpha",
            descriptor: "Sets size, swing or depth.",
            value: channel(\.amplitude), range: 0...1, step: 0.01, precision: 2,
            color: OrbitTheme.dialAmplitude)
          GlassKnob(
            title: "Frequency", symbol: "ν", symbolName: "nu",
            descriptor: "Base cycles per second at 1×.",
            value: channel(\.frequency), range: 0.01...1, step: 0.01,
            unit: "Hz", precision: 2, color: OrbitTheme.dialFrequency)
          GlassKnob(
            title: "Phase", symbol: "φ", symbolName: "phi",
            descriptor: "Offsets angles within the motion.",
            value: channel(\.phase), range: 0...360, step: 1, unit: "°",
            precision: 0, color: OrbitTheme.dialPhase)
        }
      }
      Text(
        model.linked
          ? "All channels share the same motion settings."
          : "Drag a dial up or right. Fine-tune with its slider."
      )
      .font(.caption).foregroundStyle(OrbitTheme.muted).frame(
        maxWidth: .infinity, alignment: .leading
      ).frame(minHeight: 32)
    }
  }
  private var motion: Motion { model.settings.channels[model.selectedChannel].motion }
  private var matchingHarmonic: HarmonicPreset? {
    model.currentHarmonic
  }

  private var harmonicPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Menu {
        Section("Start a harmonic · new recording") {
          ForEach(HarmonicPreset.allCases) { preset in
            Button {
              OrbitalHaptics.shared.success()
              model.applyHarmonic(preset)
            } label: {
              Text(preset.title)
              Text(preset.ratioLabel)
            }
          }
        }
        Section {
          Button("Zero all phase offsets", systemImage: "arrow.triangle.merge") {
            OrbitalHaptics.shared.selection()
            model.alignPhases()
          }
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "waveform.path")
          VStack(alignment: .leading, spacing: 3) {
            Text(matchingHarmonic?.title ?? "Harmonic starters")
              .font(.subheadline.weight(.semibold))
            Text(matchingHarmonic?.ratioLabel ?? "Choose a synchronization")
              .font(.system(.caption, design: .monospaced))
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
        }
        .padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.glass).tint(OrbitTheme.amber)
      .accessibilityLabel("Harmonic presets")
      .accessibilityValue(matchingHarmonic?.title ?? "Custom")
      .accessibilityIdentifier("harmonic-picker")
      .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
      Text("Starters set A, B & C and begin a fresh recording.")
        .font(.caption).foregroundStyle(OrbitTheme.muted)
    }
  }

  private var motionSelector: some View {
    VStack(alignment: .leading, spacing: 8) {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 6),
          count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 7
      ) {
        ForEach(Motion.allCases) { choice in
          Button {
            OrbitalHaptics.shared.selection()
            model.setChannel(\.motion, choice)
          } label: {
            Text(choice.rawValue)
              .font(.caption.weight(motion == choice ? .bold : .medium))
              .frame(maxWidth: .infinity, minHeight: 44)
              .fixedSize(horizontal: false, vertical: true)
          }
          .buttonStyle(.plain)
          .foregroundStyle(motion == choice ? OrbitTheme.background : .white.opacity(0.85))
          .background(
            motion == choice ? OrbitTheme.channels[model.selectedChannel] : .white.opacity(0.07),
            in: .rect(cornerRadius: 14)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 14)
              .strokeBorder(
                OrbitTheme.channels[model.selectedChannel].opacity(motion == choice ? 0.8 : 0.18))
          }
          .glassEffect(
            .regular.tint(OrbitTheme.channels[model.selectedChannel].opacity(0.12)).interactive(),
            in: .rect(cornerRadius: 14)
          )
          .accessibilityAddTraits(motion == choice ? .isSelected : [])
          .accessibilityIdentifier("motion-choice-\(choice.rawValue)")
        }
      }
      .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: motion)
      Text(motionExplanation)
        .font(.caption).foregroundStyle(OrbitTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: modeDescriptorHeight, alignment: .topLeading)
        .accessibilityIdentifier("motion-mode-description")
    }
  }

  private var motionExplanation: String {
    let channel = model.settings.channels[model.selectedChannel]
    if channel.speed == 0 {
      return
        "\(motion.rawValue) · Speed is zero. Raise κ to move; dashed paths still show the motion."
    }
    if channel.amplitude == 0 && motion != .orbit {
      return "\(motion.rawValue) · Amplitude is zero. Raise α to reveal this motion’s shape."
    }
    return switch motion {
    case .orbit: "Orbit · Circles at a steady rate. Amplitude sets latitude in 3D and depth in 4D."
    case .pendulum: "Pendulum · Swings back and forth. Amplitude sets the maximum swing."
    case .precession:
      "Precession · A tilted orbit slowly turns. Raise amplitude and choose 3D to reveal the tilt."
    case .lissajous: "Lissajous · Intersecting 2:3 harmonics. Amplitude sets the pattern’s size."
    case .breathing:
      "Breathing · An orbit pulses inward and outward. Amplitude sets the pulse depth."
    }
  }

  private func channel(_ key: WritableKeyPath<Channel, Double>) -> Binding<Double> {
    Binding(
      get: { model.settings.channels[model.selectedChannel][keyPath: key] },
      set: { model.setChannel(key, $0) })
  }
}
