import CoreGraphics
import simd

/// Projects the existing mathematical geometry into an ARKit camera viewport.
/// The host supplies ARKit's orientation-aware Metal view/projection matrix and
/// an anchor-relative model transform in meters. No instrument camera is applied.
struct ARSceneProjection {
  let viewProjection: simd_float4x4
  let modelTransform: simd_float4x4
  private let modelViewProjection: simd_float4x4

  init(viewProjection: simd_float4x4, modelTransform: simd_float4x4) {
    self.viewProjection = viewProjection
    self.modelTransform = modelTransform
    modelViewProjection = viewProjection * modelTransform
  }

  func project(_ point: Vec3, viewport: CGSize) -> SIMD2<Float>? {
    guard viewport.width.isFinite, viewport.height.isFinite,
      viewport.width > 0, viewport.height > 0,
      point.x.isFinite, point.y.isFinite, point.z.isFinite
    else { return nil }
    let clip = modelViewProjection * SIMD4<Float>(Float(point.x), Float(point.y), Float(point.z), 1)
    // Metal's visible depth interval is 0...w. Cull before dividing so geometry
    // behind the viewer or crossing the near plane cannot produce inverted rays.
    guard clip.x.isFinite, clip.y.isFinite, clip.z.isFinite, clip.w.isFinite,
      clip.w > 0.000_001, clip.z >= 0, clip.z <= clip.w
    else { return nil }
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    let pixel = SIMD2(
      (ndc.x + 1) * 0.5 * Float(viewport.width),
      (1 - ndc.y) * 0.5 * Float(viewport.height))
    return pixel.x.isFinite && pixel.y.isFinite ? pixel : nil
  }
}
