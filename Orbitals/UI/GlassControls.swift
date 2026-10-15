import SwiftUI

/// A native Liquid Glass rotary control with a direct linear alternative below it.
struct GlassKnob: View {
  let title: String
  var symbol = ""
  var symbolName = ""
  var descriptor = ""
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  var unit = ""
  var precision = 2
  var color: Color = OrbitTheme.amber

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @GestureState private var isDragging = false
  @State private var startingValue: Double?
  @FocusState private var hasKeyboardFocus: Bool
  @ScaledMetric(relativeTo: .caption) private var descriptorHeight = 36.0

  private var position: Double { normalized(value, in: range) }
  private var reading: String { formatted(value, precision: precision, unit: unit) }

  var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if !symbol.isEmpty {
          Text(symbol)
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
        }
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(color)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(symbolName.isEmpty ? title : "\(title), \(symbolName)")

      if !descriptor.isEmpty {
        Text(descriptor)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.75))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(minHeight: descriptorHeight, alignment: .top)
      }

      dial
        .frame(width: 104, height: 104)
        .contentShape(Circle())
        .gesture(adjustmentGesture)
        .focusable()
        .focused($hasKeyboardFocus)
        .onKeyPress(.upArrow) {
          nudge(1)
          return .handled
        }
        .onKeyPress(.rightArrow) {
          nudge(1)
          return .handled
        }
        .onKeyPress(.downArrow) {
          nudge(-1)
          return .handled
        }
        .onKeyPress(.leftArrow) {
          nudge(-1)
          return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(reading)
        .accessibilityHint(
          "\(descriptor) Swipe up or down to adjust. Drag the dial up or right to increase."
        )
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment: nudge(1)
          case .decrement: nudge(-1)
          @unknown default: break
          }
        }

      Text(reading)
        .font(.system(.title3, design: .monospaced).weight(.semibold))
        .foregroundStyle(color)
        .monospacedDigit()
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityHidden(true)

      Slider(value: tactileBinding, in: range, step: max(step, .ulpOfOne)) { editing in
        if editing {
          OrbitalHaptics.shared.beginAdjustment()
        } else {
          OrbitalHaptics.shared.endAdjustment()
        }
      }
      .tint(color)
      .frame(minHeight: 44)
      .accessibilityLabel("\(title), linear control")
      .accessibilityValue(reading)
      .accessibilityHint(descriptor)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 8)
    .padding(.vertical, 14)
    .background(color.opacity(0.055), in: .rect(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .strokeBorder(color.opacity(isDragging ? 0.58 : 0.22), lineWidth: 1)
        .allowsHitTesting(false)
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: startingValue != nil)
    .onChange(of: isDragging) { _, dragging in
      // Also releases correctly if a scroll view or system gesture cancels.
      if !dragging { finishAdjustment() }
    }
    .onDisappear { startingValue = nil }
  }

  private var dial: some View {
    ZStack {
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0...30 {
          let angle = (-135 + Double(index) * 9) * .pi / 180
          let major = index.isMultiple(of: 5)
          let outer = size.width / 2 - 2
          let inner = outer - (major ? 7 : 3)
          var path = Path()
          path.move(to: CGPoint(x: center.x + sin(angle) * inner, y: center.y - cos(angle) * inner))
          path.addLine(
            to: CGPoint(x: center.x + sin(angle) * outer, y: center.y - cos(angle) * outer))
          context.stroke(
            path, with: .color(color.opacity(Double(index) / 30 <= position ? 0.8 : 0.22)),
            lineWidth: major ? 1.6 : 1)
        }
      }
      .accessibilityHidden(true)

      Circle()
        .trim(from: 0, to: 0.75)
        .stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(135))
        .frame(width: 84, height: 84)
      Circle()
        .trim(from: 0, to: 0.75 * position)
        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(135))
        .frame(width: 84, height: 84)
        .shadow(color: color.opacity(0.28), radius: 4)

      ZStack {
        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        Capsule()
          .fill(color)
          .frame(width: 4, height: 14)
          .offset(y: -23)
          .rotationEffect(.degrees(-135 + 270 * position))
        Circle().fill(color.opacity(0.75)).frame(width: 4, height: 4)
      }
      .frame(width: 70, height: 70)
      .glassEffect(.regular.tint(color.opacity(0.22)).interactive(), in: .circle)
      .scaleEffect(startingValue == nil ? 1 : 1.045)
    }
  }

  private var adjustmentGesture: some Gesture {
    DragGesture(minimumDistance: 2)
      .updating($isDragging) { _, state, _ in state = true }
      .onChanged { gesture in
        if startingValue == nil {
          startingValue = value
          hasKeyboardFocus = true
          OrbitalHaptics.shared.beginAdjustment()
        }
        let movement = Double(gesture.translation.width - gesture.translation.height)
        let next = (startingValue ?? value) + movement / 240 * (range.upperBound - range.lowerBound)
        setValue(next)
      }
      .onEnded { _ in finishAdjustment() }
  }

  private var tactileBinding: Binding<Double> {
    Binding(get: { value }, set: { setValue($0) })
  }

  private func setValue(_ proposed: Double) {
    let next = quantized(proposed, range: range, step: step)
    guard value != next else { return }
    value = next
    if voiceOverEnabled {
      OrbitalHaptics.shared.selection()
    } else {
      OrbitalHaptics.shared.detent(normalized: normalized(next, in: range))
    }
  }

  private func nudge(_ direction: Double) {
    let previous = value
    let next = quantized(value + direction * step, range: range, step: step)
    guard previous != next else {
      OrbitalHaptics.shared.boundary()
      return
    }
    value = next
    OrbitalHaptics.shared.selection()
  }

  private func finishAdjustment() {
    guard startingValue != nil else { return }
    startingValue = nil
    OrbitalHaptics.shared.endAdjustment()
  }
}

struct GlassSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  var step = 0.01
  var unit = ""
  var precision = 2
  var color: Color = OrbitTheme.amber

  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

  private var reading: String { formatted(value, precision: precision, unit: unit) }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          Text(title).font(.subheadline)
          Spacer(minLength: 12)
          readout
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.subheadline)
          readout
        }
      }
      Slider(value: tactileBinding, in: range, step: max(step, .ulpOfOne)) { editing in
        if editing {
          OrbitalHaptics.shared.beginAdjustment()
        } else {
          OrbitalHaptics.shared.endAdjustment()
        }
      }
      .tint(color)
      .frame(minHeight: 44)
      .accessibilityLabel(title)
      .accessibilityValue(reading)
    }
  }

  private var readout: some View {
    Text(reading)
      .font(.system(.subheadline, design: .monospaced).weight(.medium))
      .foregroundStyle(color)
      .monospacedDigit()
      .fixedSize(horizontal: true, vertical: false)
      .contentTransition(.numericText())
      .accessibilityHidden(true)
  }

  private var tactileBinding: Binding<Double> {
    Binding(
      get: { value },
      set: { proposed in
        let next = quantized(proposed, range: range, step: step)
        guard value != next else { return }
        value = next
        if voiceOverEnabled {
          OrbitalHaptics.shared.selection()
        } else {
          OrbitalHaptics.shared.detent(normalized: normalized(next, in: range))
        }
      })
  }
}

struct GlassToggle: View {
  let title: String
  @Binding var isOn: Bool
  let symbol: String

  var body: some View {
    Toggle(
      isOn: Binding(
        get: { isOn },
        set: { next in
          guard next != isOn else { return }
          OrbitalHaptics.shared.selection()
          isOn = next
        })
    ) {
      Label(title, systemImage: symbol)
        .font(.subheadline)
        .symbolRenderingMode(.hierarchical)
        .fixedSize(horizontal: false, vertical: true)
    }
    .tint(OrbitTheme.phosphor)
    .frame(minHeight: 44)
    .accessibilityLabel(title)
  }
}

struct ActionButton: View {
  let title: String
  let symbol: String
  var prominent = false
  var tint: Color = OrbitTheme.phosphor
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if prominent {
        button.buttonStyle(.glassProminent)
      } else {
        button.buttonStyle(.glass)
      }
    }
    .tint(tint)
    .accessibilityLabel(title)
  }

  private var button: some View {
    Button {
      OrbitalHaptics.shared.tap()
      if reduceMotion { action() } else { withAnimation(.smooth(duration: 0.2)) { action() } }
    } label: {
      Label {
        Text(title)
          .lineLimit(1)
      } icon: {
        Image(systemName: symbol)
          .contentTransition(.symbolEffect(.replace))
      }
      .font(.subheadline.weight(.semibold))
      .fixedSize(horizontal: true, vertical: false)
      .frame(minWidth: 24, minHeight: 32)
      .padding(.horizontal, 4)
      .padding(.vertical, 6)
    }
    .buttonBorderShape(.capsule)
    .symbolEffectsRemoved(reduceMotion)
    .transaction { if reduceMotion { $0.animation = nil } }
  }
}

private func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
  guard value.isFinite, range.upperBound > range.lowerBound else { return 0 }
  return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
}

private func quantized(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
  guard value.isFinite else { return range.lowerBound }
  let interval = max(step, .ulpOfOne)
  let rounded = range.lowerBound + ((value - range.lowerBound) / interval).rounded() * interval
  return min(range.upperBound, max(range.lowerBound, rounded))
}

private func formatted(_ value: Double, precision: Int, unit: String) -> String {
  let digits = min(6, max(0, precision))
  let number = value.formatted(.number.precision(.fractionLength(digits)))
  return unit.isEmpty ? number : "\(number) \(unit)"
}
