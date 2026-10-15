import Foundation
import simd

enum TorusMath {
  static let torusRadius = 2.6
  static let tubeGain = 0.26
  static let tubeRadius = 0.88
  static let seamHalfAngle = 0.14

  /// Time is a display coordinate. The back arc closes the image, not the archive.
  static func timeAngle(offset: Double, horizon: Double) -> Double {
    .pi / 2 - (.pi - seamHalfAngle) * offset / max(horizon, .leastNonzeroMagnitude)
  }

  static func tubePoint(offset: Double, horizon: Double, u: Double, v: Double) -> Vec3 {
    let theta = timeAngle(offset: offset, horizon: horizon)
    return Vec3((torusRadius + u) * cos(theta), v, (torusRadius + u) * sin(theta))
  }

  /// A fixed 4D eye and orthonormal oblique axes keep history independent of today's radius.
  static func projectCrossSection(_ position: Vec4) -> SIMD2<Double> {
    let factor = 9 / (9 - position.w)
    let p = position * factor
    return SIMD2(tubeGain * (p.x - p.z) / sqrt(2), tubeGain * (p.x + 2 * p.y + p.z) / sqrt(6))
  }

  static func projectToTorus(_ position: Vec4, offset: Double, horizon: Double) -> Vec3 {
    let uv = projectCrossSection(position)
    return tubePoint(offset: offset, horizon: horizon, u: uv.x, v: uv.y)
  }

  static func closedTubePoint(phase: Double, u: Double, v: Double) -> Vec3 {
    let theta = .pi / 2 - OrbitalMath.tau * phase
    return Vec3((torusRadius + u) * cos(theta), v, (torusRadius + u) * sin(theta))
  }

  /// A bounded Bézier bridge joins the projected endpoints. It is explicitly display-only.
  static func closureBridge(
    end: Vec4, beforeEnd: Vec4, start: Vec4, afterStart: Vec4,
    tangentScale: Double
  ) -> [Vec3] {
    let a = projectCrossSection(end)
    let b = projectCrossSection(start)
    let previous = projectCrossSection(beforeEnd)
    let next = projectCrossSection(afterStart)
    func boundedControl(_ base: SIMD2<Double>, _ delta: SIMD2<Double>) -> SIMD2<Double> {
      var low = 0.0
      var high = 1.0
      for _ in 0..<20 {
        let t = (low + high) / 2
        if simd_length(base + t * delta) <= tubeRadius { low = t } else { high = t }
      }
      return base + low * delta
    }
    let c = boundedControl(a, (a - previous) * tangentScale)
    let d = boundedControl(b, (b - next) * tangentScale)
    return (0...40).map { index in
      let t = Double(index) / 40
      let r = 1 - t
      let uv = r * r * r * a + 3 * r * r * t * c + 3 * r * t * t * d + t * t * t * b
      let theta = -.pi / 2 + seamHalfAngle - 2 * seamHalfAngle * t
      return Vec3((torusRadius + uv.x) * cos(theta), uv.y, (torusRadius + uv.x) * sin(theta))
    }
  }

  static func torusScreen(_ point: Vec3, tilt: Double) -> SIMD2<Double> {
    let angle = OrbitalMath.radians(tilt)
    return SIMD2(point.x, point.z * sin(angle) - point.y * cos(angle))
  }

  static func offsetFromTorus(x: Double, y: Double, tilt: Double, horizon: Double) -> Double {
    let sine = sin(OrbitalMath.radians(tilt))
    guard abs(sine) > 1e-12 else { return 0 }
    let angle = atan2(y / sine, x)
    var delta = .pi / 2 - angle
    if delta > .pi { delta -= OrbitalMath.tau }
    return max(-horizon, min(horizon, delta / (.pi - seamHalfAngle) * horizon))
  }
}

enum CameraMath {
  static func rotate(_ point: Vec3, yaw: Double, pitch: Double) -> Vec3 {
    let a = OrbitalMath.radians(yaw)
    let b = OrbitalMath.radians(pitch)
    let x = point.x * cos(a) + point.z * sin(a)
    let z = -point.x * sin(a) + point.z * cos(a)
    return Vec3(x, point.y * cos(b) - z * sin(b), point.y * sin(b) + z * cos(b))
  }

  static func cylinderScale(width: Double, height: Double, yaw: Double, pitch: Double) -> Double {
    var xBound = 0.0
    var yBound = 0.0
    for x in [-2.8, 2.8] {
      for y in [-1.2, 1.2] {
        for z in [-1.2, 1.2] {
          let v = rotate(Vec3(x, y, z), yaw: yaw, pitch: pitch)
          xBound = max(xBound, abs(v.x))
          yBound = max(yBound, abs(v.y))
        }
      }
    }
    return max(0, min((width - 44) / (2 * xBound), (height - 88) / (2 * yBound)))
  }
}
