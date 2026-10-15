import XCTest
import simd

@testable import Orbitals

final class ARPlacementMathTests: XCTestCase {
  private func point(_ value: SIMD3<Float>, transformedBy matrix: simd_float4x4) -> SIMD3<Float> {
    let result = matrix * SIMD4(value, 1)
    return SIMD3(result.x, result.y, result.z)
  }

  private func corners(_ bounds: SIMD3<Float>) -> [SIMD3<Float>] {
    [-1.0, 1.0].flatMap { (x: Float) in
      [-1.0, 1.0].flatMap { (y: Float) in
        [-1.0, 1.0].map { (z: Float) in SIMD3(x, y, z) * bounds }
      }
    }
  }

  func testEveryShapeStaysAboveHorizontalSurface() {
    var anchor = matrix_identity_float4x4
    anchor.columns.3 = SIMD4(0.8, 0.7, -1.5, 1)
    var settings = OrbitalSettings()
    settings.radius = 3
    settings.fourD = true
    for kind in OrbitalViewKind.allCases {
      let bounds = ARPlacementMath.halfExtents(kind: kind, settings: settings)
      for size in [0.15, 0.65, 2.0] {
        let transform = ARPlacementMath.transform(
          anchor: anchor, kind: kind, settings: settings, sizeMeters: size, yaw: 1.1)
        let center = point(.zero, transformedBy: transform)
        XCTAssertGreaterThan(center.y, anchor.columns.3.y)
        let lowest = corners(bounds).map { point($0, transformedBy: transform).y }.min()!
        XCTAssertEqual(
          lowest - anchor.columns.3.y, ARPlacementMath.surfaceClearance, accuracy: 1e-6)
      }
    }
  }

  func testEveryShapeStaysInFrontOfVerticalSurface() {
    var wall = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
    wall.columns.3 = SIMD4(-0.3, 1.4, -2, 1)
    let wallOrigin = SIMD3(wall.columns.3.x, wall.columns.3.y, wall.columns.3.z)
    let normal = SIMD3(wall.columns.1.x, wall.columns.1.y, wall.columns.1.z)
    let settings = OrbitalSettings()
    for kind in OrbitalViewKind.allCases {
      let bounds = ARPlacementMath.halfExtents(kind: kind, settings: settings)
      let transform = ARPlacementMath.transform(
        anchor: wall, kind: kind, settings: settings, sizeMeters: 0.65, yaw: -.pi / 3)
      let distances = corners(bounds).map {
        simd_dot(point($0, transformedBy: transform) - wallOrigin, normal)
      }
      XCTAssertEqual(distances.min()!, ARPlacementMath.surfaceClearance, accuracy: 1e-6)
      XCTAssertGreaterThan(simd_dot(point(.zero, transformedBy: transform) - wallOrigin, normal), 0)
    }
  }

  func testRadiusDialChangesWorldSpaceDistanceInsteadOfBeingNormalizedAway() {
    for fourD in [false, true] {
      var small = OrbitalSettings()
      small.radius = 1
      small.fourD = fourD
      var large = small
      large.radius = 2
      let smallTransform = ARPlacementMath.transform(
        anchor: matrix_identity_float4x4, kind: .spatial, settings: small,
        sizeMeters: 0.65, yaw: 0.4)
      let largeTransform = ARPlacementMath.transform(
        anchor: matrix_identity_float4x4, kind: .spatial, settings: large,
        sizeMeters: 0.65, yaw: 0.4)
      let smallRadius = simd_distance(
        point([1, 0, 0], transformedBy: smallTransform), point(.zero, transformedBy: smallTransform)
      )
      let largeRadius = simd_distance(
        point([2, 0, 0], transformedBy: largeTransform), point(.zero, transformedBy: largeTransform)
      )
      XCTAssertEqual(largeRadius, smallRadius * 2, accuracy: 1e-6)
      XCTAssertEqual(largeTransform.columns.0, smallTransform.columns.0)
    }
  }

  func testYawPreservesPlacedCenterAndSupportHeight() {
    let settings = OrbitalSettings()
    for kind in OrbitalViewKind.allCases {
      let bounds = ARPlacementMath.halfExtents(kind: kind, settings: settings)
      let initial = ARPlacementMath.transform(
        anchor: matrix_identity_float4x4, kind: kind, settings: settings,
        sizeMeters: 0.65, yaw: 0)
      let rotated = ARPlacementMath.transform(
        anchor: matrix_identity_float4x4, kind: kind, settings: settings,
        sizeMeters: 0.65, yaw: .pi / 2)
      XCTAssertEqual(point(.zero, transformedBy: initial), point(.zero, transformedBy: rotated))
      XCTAssertEqual(
        point([0, -bounds.y, 0], transformedBy: initial),
        point([0, -bounds.y, 0], transformedBy: rotated))
      let initialPoint = point([1, 0, 0], transformedBy: initial)
      let rotatedPoint = point([1, 0, 0], transformedBy: rotated)
      let center = point(.zero, transformedBy: initial)
      XCTAssertEqual(
        simd_distance(initialPoint, center), simd_distance(rotatedPoint, center), accuracy: 1e-6)
      XCTAssertGreaterThan(simd_distance(initialPoint, rotatedPoint), 0.01)
    }
  }

  func testBoundsIncludeLiveRadiusAndRemainFiniteForMalformedValues() {
    var settings = OrbitalSettings()
    for radius in [0.5, 1.0, 2.0, 3.0] {
      settings.radius = radius
      for fourD in [false, true] {
        settings.fourD = fourD
        let bound = ARPlacementMath.halfExtents(kind: .spatial, settings: settings)
        XCTAssertEqual(bound.y, Float(radius * (fourD ? 1.5 : 1.1)), accuracy: 1e-6)
      }
    }
    for radius in [Double.nan, .infinity, -.infinity, -1, 0, .greatestFiniteMagnitude] {
      settings.radius = radius
      for kind in OrbitalViewKind.allCases {
        let bound = ARPlacementMath.halfExtents(kind: kind, settings: settings)
        XCTAssertTrue(bound.x.isFinite && bound.y.isFinite && bound.z.isFinite)
        XCTAssertGreaterThan(bound.x, 0)
        XCTAssertGreaterThan(bound.y, 0)
        XCTAssertGreaterThan(bound.z, 0)
      }
    }
  }
}
