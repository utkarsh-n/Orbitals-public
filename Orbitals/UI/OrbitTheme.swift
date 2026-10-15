import SwiftUI

enum OrbitTheme {
  static let background = Color(red: 0.025, green: 0.045, blue: 0.04)
  static let panel = Color(red: 0.065, green: 0.095, blue: 0.083)
  static let phosphor = Color(red: 0.4, green: 0.96, blue: 0.56)
  static let amber = Color(red: 1, green: 0.75, blue: 0.37)
  static let cyan = Color(red: 0.57, green: 0.89, blue: 1)
  static let channelCyan = Color(red: 0.1, green: 0.93, blue: 1)
  static let magenta = Color(red: 1, green: 0.18, blue: 0.78)
  static let yellow = Color(red: 1, green: 0.91, blue: 0.18)
  static let muted = Color(red: 0.61, green: 0.71, blue: 0.65)
  static let channels = [channelCyan, magenta, yellow]
  static let channelNames = ["Cyan", "Magenta", "Yellow"]
  // Control accents identify a parameter independently of the edited CMY channel.
  static let dialSpeed = Color(red: 1, green: 0.69, blue: 0.30)
  static let dialAmplitude = Color(red: 0.38, green: 0.70, blue: 1)
  static let dialFrequency = Color(red: 0.35, green: 0.94, blue: 0.69)
  static let dialPhase = Color(red: 0.78, green: 0.60, blue: 1)
}

struct InstrumentPanel<Content: View>: View {
  let title: String
  let number: String
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        Text(number).foregroundStyle(OrbitTheme.phosphor)
        Text(title.uppercased()).tracking(2)
        Spacer(minLength: 0)
      }
      .font(.system(.caption, design: .monospaced).weight(.medium))
      .foregroundStyle(OrbitTheme.muted)
      content
    }
    .padding(20)
    .background(OrbitTheme.panel, in: .rect(cornerRadius: 26))
    .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.07)) }
  }
}

struct Readout: View {
  let title: String
  let value: String
  var color: Color = OrbitTheme.amber
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title.uppercased()).font(.system(.caption2, design: .monospaced)).foregroundStyle(
        OrbitTheme.muted)
      Text(value).font(.system(.callout, design: .monospaced).weight(.medium)).monospacedDigit()
        .foregroundStyle(color)
        .contentTransition(.numericText())
    }.accessibilityElement(children: .combine)
  }
}
