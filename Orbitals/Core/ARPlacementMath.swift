import simd

/// Converts instrument units to meters without normalizing away changes to the
/// experiment's radius. Reference spans set the initial AR size; live bounds
/// affect only clearance above the chosen surface.
enum ARPlacementMath {
  static let surfaceClearance: Float = 0.015

  static func referenceSpan(for kind: OrbitalViewKind) -> Float {
    switch kind {
    case .spatial: 6
    case .cylinder: 5.6
    case .torus, .tracks, .retcon: 6.96
    }
  }

  static func halfExtents(kind: OrbitalViewKind, settings: OrbitalSettings) -> SIMD3<Float> {
    switch kind {
    case .spatial:
      // Valid experiments use 0.5...3. Fall back defensively if malformed data
      // would otherwise put nonfinite values into a world transform.
      let rawRadius = Float(settings.radius)
      let radius =
        rawRadius.isFinite && rawRadius > 0 && rawRadius < Float.greatestFiniteMagnitude / 2
        ? rawRadius : 2
      let bound = radius * (settings.fourD ? 1.5 : 1.1)
      return SIMD3(repeating: bound)
    case .cylinder:
      return SIMD3(2.8, 1.2, 1.2)
    case .torus, .tracks, .retcon:
      // The torus axes reach ±1.2 in Y, beyond its 0.88 tube radius.
      return SIMD3(3.48, 1.2, 3.48)
    }
  }

  static func transform(
    anchor: simd_float4x4, kind: OrbitalViewKind, settings: OrbitalSettings,
    sizeMeters: Double, yaw: Float
  ) -> simd_float4x4 {
    let rawSize = Float(sizeMeters)
    let size = rawSize.isFinite && rawSize > 0 ? rawSize : 0.65
    let scale = size / referenceSpan(for: kind)
    let bounds = halfExtents(kind: kind, settings: settings)
    var lift = matrix_identity_float4x4
    // A raycast's local Y points out of its surface. This places the entire
    // shape above a table or in front of a wall, with a small luminous gap.
    lift.columns.3.y = bounds.y * scale + surfaceClearance
    let rotation = simd_float4x4(
      simd_quatf(angle: yaw.isFinite ? yaw : 0, axis: [0, 1, 0]))
    let scaling = simd_float4x4(diagonal: SIMD4(scale, scale, scale, 1))
    return anchor * lift * rotation * scaling
  }
}
