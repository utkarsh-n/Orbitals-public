import Foundation
import simd

typealias Vec4 = SIMD4<Double>
typealias Vec3 = SIMD3<Double>

enum Motion: String, CaseIterable, Codable, Identifiable, Sendable {
  case orbit = "Orbit"
  case pendulum = "Pendulum"
  case precession = "Precession"
  case lissajous = "Lissajous"
  case breathing = "Breathing"

  var id: Self { self }
}

struct Channel: Codable, Equatable, Hashable, Sendable {
  var motion: Motion
  var speed: Double
  var amplitude: Double
  var frequency: Double
  var phase: Double

  init(
    motion: Motion = .orbit, speed: Double = 1, amplitude: Double = 0.7,
    frequency: Double = 0.12, phase: Double = 0
  ) {
    self.motion = motion
    self.speed = speed
    self.amplitude = amplitude
    self.frequency = frequency
    self.phase = phase
  }
}

struct OrbitalSettings: Codable, Equatable, Hashable, Sendable {
  var morph: Double = 0
  var radius: Double = 2
  var yaw: Double = 0
  var pitch: Double = 0
  var trails = true
  var persistence: Double = 3
  var glow: Double = 0.65
  var mesh = true
  var axes = true
  var connections = true
  var fourD = false
  var xw: Double = 25
  var yw: Double = 0
  var zw: Double = 0
  var channels: [Channel] = [0, 120, 240].map { Channel(phase: $0) }
}

/// Only values that affect physical coordinates; presentation changes never split history.
struct MotionSignature: Equatable, Hashable, Sendable {
  var channels: [Channel]
  var radius: Double
  var morph: Double
  var fourD: Bool
  var xw: Double
  var yw: Double
  var zw: Double

  init(_ settings: OrbitalSettings) {
    channels = settings.channels
    radius = settings.radius
    morph = settings.morph
    fourD = settings.fourD
    xw = settings.xw
    yw = settings.yw
    zw = settings.zw
  }
}

enum OrbitalMath {
  static let tau = 2 * Double.pi

  static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
  static func norm(_ vector: Vec4) -> Double { simd_length(vector) }
  static func distance(_ a: Vec4, _ b: Vec4) -> Double { simd_distance(a, b) }

  static func rotatePlane(_ v: Vec4, i: Int, j: Int, angle: Double) -> Vec4 {
    var result = v
    let c = cos(angle)
    let s = sin(angle)
    result[i] = v[i] * c - v[j] * s
    result[j] = v[i] * s + v[j] * c
    return result
  }

  static func rotate4(_ v: Vec4, settings s: OrbitalSettings) -> Vec4 {
    guard s.fourD else { return v }
    let x = rotatePlane(v, i: 0, j: 3, angle: radians(s.xw))
    let y = rotatePlane(x, i: 1, j: 3, angle: radians(s.yw))
    return rotatePlane(y, i: 2, j: 3, angle: radians(s.zw))
  }

  /// Latitude opens continuously from an equatorial circle to S²; w opens S³.
  static func surface(
    theta: Double, latitude: Double, wAngle: Double,
    settings s: OrbitalSettings, radius: Double? = nil
  ) -> Vec4 {
    let r = radius ?? s.radius
    let latitude = latitude * s.morph
    let w = s.fourD ? wAngle : 0
    let cw = cos(w)
    let cl = cos(latitude)
    return rotate4(
      Vec4(
        r * cw * cl * cos(theta), r * cw * cl * sin(theta),
        r * cw * sin(latitude), r * sin(w)), settings: s)
  }

  static func pointAt(_ t: Double, index: Int, settings s: OrbitalSettings) -> Vec4 {
    pointAt(t, channel: s.channels[index], settings: s)
  }

  /// Evaluates a channel value directly so cached track construction avoids array copies.
  static func pointAt(_ t: Double, channel: Channel, settings s: OrbitalSettings) -> Vec4 {
    let phase = radians(channel.phase)
    let q = tau * channel.frequency * channel.speed * t
    let amplitude = channel.amplitude
    var theta = q + phase
    var latitude = 0.0
    var wAngle = 0.0
    var radius = s.radius
    switch channel.motion {
    case .orbit:
      latitude = cos(phase) * 0.65 * amplitude
      wAngle = cos(phase) * 0.4 * amplitude
    case .pendulum:
      let swing = amplitude * 1.4 * sin(q)
      let v = rotatePlane(Vec4(cos(swing), sin(swing), 0, 0), i: 1, j: 2, angle: 0.7)
      theta = phase + atan2(v.y, v.x)
      latitude = asin(max(-1, min(1, v.z)))
    case .precession:
      let inclined = rotatePlane(Vec4(cos(q), sin(q), 0, 0), i: 0, j: 2, angle: amplitude * 1.2)
      let v = rotatePlane(inclined, i: 0, j: 1, angle: q * 0.25 + phase)
      theta = atan2(v.y, v.x)
      latitude = asin(max(-1, min(1, v.z)))
      wAngle = s.fourD ? amplitude * 0.5 * sin(q * 0.5) : 0
    case .breathing:
      radius *= 1 - amplitude * 0.45 * (1 - cos(q))
      latitude = sin(phase) * 0.7
      wAngle = amplitude * 0.6 * sin(q * 0.5)
    case .lissajous:
      // Bounded 2:3:4:5 harmonics; no normalization that would change the curve.
      let scale = s.radius * amplitude / sqrt(2 + s.morph * s.morph + (s.fourD ? 1 : 0))
      return rotate4(
        Vec4(
          scale * sin(2 * q + phase), scale * sin(3 * q),
          scale * s.morph * sin(4 * q + phase),
          s.fourD ? scale * sin(5 * q + phase) : 0), settings: s)
    }
    return surface(theta: theta, latitude: latitude, wAngle: wAngle, settings: s, radius: radius)
  }

  static func pointsAt(_ t: Double, settings: OrbitalSettings) -> [Vec4] {
    settings.channels.indices.map { pointAt(t, index: $0, settings: settings) }
  }

  /// Perspective projection from an eye at w = 3R, then a 3D camera rotation.
  /// For valid settings |w| ≤ R, so the perspective denominator stays positive.
  static func project(_ v: Vec4, settings s: OrbitalSettings) -> Vec3 {
    let factor = s.fourD ? 3 * s.radius / (3 * s.radius - v.w) : 1
    return CameraMath.rotate(Vec3(v.x, v.y, v.z) * factor, yaw: s.yaw, pitch: s.pitch)
  }

  static func meshLines(settings s: OrbitalSettings) -> [[Vec4]] {
    var lines: [[Vec4]] = []
    let pi = Double.pi
    let wAngles: [Double] = s.fourD ? [-pi / 3, 0, pi / 3] : [0]
    let latitudes: [Double] =
      s.morph < 0.005 ? [0] : [-pi / 2, -pi / 3, -pi / 6, 0, pi / 6, pi / 3, pi / 2]
    lines.reserveCapacity(s.fourD ? 65 : 19)
    for w in wAngles {
      for latitude in latitudes {
        lines.append(
          (0...80).map {
            surface(theta: tau * Double($0) / 80, latitude: latitude, wAngle: w, settings: s)
          })
      }
      if s.morph > 0.005 {
        for meridian in 0..<12 {
          lines.append(
            (0...40).map {
              surface(
                theta: tau * Double(meridian) / 12,
                latitude: -.pi / 2 + .pi * Double($0) / 40, wAngle: w, settings: s)
            })
        }
      }
    }
    if s.fourD {
      for meridian in 0..<8 {
        lines.append(
          (0...80).map {
            surface(
              theta: Double(meridian) * tau / 8,
              latitude: .pi / 5, wAngle: tau * Double($0) / 80, settings: s)
          })
      }
    }
    return lines
  }
}
