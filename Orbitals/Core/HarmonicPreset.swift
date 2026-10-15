import Foundation

/// Kinematic starting points with exact, inspectable frequency and phase relations.
/// Rates are scaled for the display; these are not gravitational or coupled-oscillator simulations.
enum HarmonicPreset: String, CaseIterable, Identifiable, Sendable {
  case unison, counterphase, threePhase, laplace, beats, lissajous

  var id: Self { self }

  var title: String {
    switch self {
    case .unison: "Unison"
    case .counterphase: "Counterphase"
    case .threePhase: "Three-phase"
    case .laplace: "Jovian resonance"
    case .beats: "Slow beats"
    case .lissajous: "Lissajous harmonics"
    }
  }

  var ratioLabel: String {
    switch self {
    case .unison: "1 : 1 : 1 · 0°"
    case .counterphase: "1 : 1 : 1 · 180°"
    case .threePhase: "1 : 1 : 1 · 120°"
    case .laplace: "4 : 2 : 1"
    case .beats: "0.12 · 0.13 · 0.14 Hz"
    case .lissajous: "2 : 3 · coordinate harmonics"
    }
  }

  var summary: String {
    switch self {
    case .unison:
      "Equal rates and phases: all three nodes overlap. Zero amplitude keeps this reference circle in one plane."
    case .counterphase:
      "Magenta stays half a turn from cyan and yellow. Zero amplitude keeps the opposite phases on one circle."
    case .threePhase:
      "Equal rates, spaced 120° like balanced AC phasors. Zero amplitude keeps the rotating triangle in one plane."
    case .laplace:
      "Scaled from Io, Europa and Ganymede’s 4:2:1 orbital rates. A phase illustration, not a gravity simulation."
    case .beats:
      "Nearby rates drift into and out of alignment: adjacent channels gain one lap every 100 seconds."
    case .lissajous:
      "A harmonograph-inspired 2:3 x/y pattern, with 4th and 5th coordinate harmonics in higher dimensions."
    }
  }

  var channels: [Channel] {
    let frequencies: [Double]
    let phases: [Double]
    switch self {
    case .unison:
      frequencies = [0.12, 0.12, 0.12]
      phases = [0, 0, 0]
    case .counterphase:
      frequencies = [0.12, 0.12, 0.12]
      phases = [0, 180, 0]
    case .threePhase:
      frequencies = [0.12, 0.12, 0.12]
      phases = [0, 120, 240]
    case .laplace:
      frequencies = [0.4, 0.2, 0.1]
      // lambda_Io - 3 lambda_Europa + 2 lambda_Ganymede = 180 degrees.
      phases = [180, 0, 0]
    case .beats:
      frequencies = [0.12, 0.13, 0.14]
      phases = [0, 0, 0]
    case .lissajous:
      frequencies = [0.1, 0.1, 0.1]
      phases = [0, 120, 240]
    }
    return (0..<3).map { index in
      Channel(
        motion: self == .lissajous ? .lissajous : .orbit,
        speed: 1, amplitude: self == .lissajous ? 0.85 : 0,
        frequency: frequencies[index], phase: phases[index])
    }
  }

  var sourceTitle: String {
    switch self {
    case .unison, .counterphase, .beats: "OpenStax · Superposition and interference"
    case .threePhase: "MIT · Three-phase systems"
    case .laplace: "NASA · Ganymede facts"
    case .lissajous: "MIT · Lissajous figures and the Bowditch pendulum"
    }
  }

  var sourceURL: URL {
    let address: String
    switch self {
    case .unison, .counterphase, .beats:
      address =
        "https://openstax.org/books/college-physics-2e/pages/16-10-superposition-and-interference"
    case .threePhase:
      address =
        "https://ocw.mit.edu/courses/6-622-power-electronics-spring-2023/mit6_622_s23_lec212.pdf"
    case .laplace:
      address = "https://science.nasa.gov/jupiter/jupiter-moons/ganymede/facts/"
    case .lissajous:
      address = "https://wikis.mit.edu/confluence/pages/viewpage.action?pageId=43457493"
    }
    return URL(string: address)!
  }
}
