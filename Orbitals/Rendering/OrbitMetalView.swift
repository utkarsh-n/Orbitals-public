import MetalKit
import QuartzCore
import SwiftUI

enum OrbitalViewKind: String, CaseIterable, Identifiable {
  case spatial, cylinder, torus, tracks, retcon
  var id: String { rawValue }
  var title: String {
    switch self {
    case .spatial: "Spatial scope"
    case .cylinder: "Time cylinder"
    case .torus: "Time torus"
    case .tracks: "Orbital tracks"
    case .retcon: "Retcon torus"
    }
  }
  var subtitle: String {
    switch self {
    case .spatial: "Projected geometry"
    case .cylinder: "Recorded · now · predicted"
    case .torus: "Time wrapped into a closed ring"
    case .tracks: "Fixed paths · moving nodes"
    case .retcon: "Rewrite time · retain its echo"
    }
  }
  var symbol: String {
    switch self {
    case .spatial: "globe"
    case .cylinder: "cylinder.split.1x2"
    case .torus: "circle.hexagongrid"
    case .tracks: "point.topleft.down.to.point.bottomright.curvepath"
    case .retcon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
    }
  }
}

struct ViewCamera: Equatable {
  var yaw: Double = 0
  var pitch: Double = 0
  var zoom: Double = 1
  var panX: Double = 0
  var panY: Double = 0
}

struct RenderSnapshot {
  var settings: OrbitalSettings
  var time: Double
  var samples: [TimelineSample]
  var kind: OrbitalViewKind
  var camera: ViewCamera
  var horizon: Double
  var inspectionOffset: Double
  var planeIndices: SIMD2<Int>
  var loopEnabled: Bool
  var loopProgram: LoopProgram
  var loopEpoch: Double
  var loopOrigins: [Double]
  var retconPhase: Double
  var ghostStrength: Double
  var trailCutoff: Double
}

@MainActor
protocol OrbitalSceneSource: AnyObject {
  func renderSnapshot() -> RenderSnapshot
  func advanceFrame(timestamp: Double)
  var isAnimating: Bool { get }
}

/// Only the visible visualization has a display link. Paused control changes request
/// one frame; Metal buffers are retained and reused rather than allocated each tick.
struct OrbitMetalView: UIViewRepresentable {
  let source: any OrbitalSceneSource
  var redrawKey: Int
  var running: Bool
  var onError: (String) -> Void

  final class Coordinator {
    var renderer: OrbitRenderer?
    var lastKey = Int.min
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> MTKView {
    let view = OrbitMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    view.backgroundColor = UIColor(red: 0.025, green: 0.049, blue: 0.041, alpha: 1)
    view.isOpaque = true
    view.framebufferOnly = true
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 1
    view.autoResizeDrawable = true
    view.isAccessibilityElement = false
    // Gesture, VoiceOver and keyboard controls are supplied by the SwiftUI host.
    view.isUserInteractionEnabled = false
    do {
      let renderer = try OrbitRenderer(view: view, source: source)
      view.delegate = renderer
      context.coordinator.renderer = renderer
    } catch {
      Task { @MainActor in onError(error.localizedDescription) }
    }
    updateUIView(view, context: context)
    return view
  }

  func updateUIView(_ view: MTKView, context: Context) {
    context.coordinator.renderer?.source = source
    view.preferredFramesPerSecond = OrbitRenderer.preferredFrameRate
    view.enableSetNeedsDisplay = !running
    view.isPaused = !running
    if context.coordinator.lastKey != redrawKey || !running {
      context.coordinator.lastKey = redrawKey
      view.setNeedsDisplay()
    }
  }

  static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
    view.isPaused = true
    view.delegate = nil
    coordinator.renderer = nil
    view.releaseDrawables()
  }
}

private final class OrbitMTKView: MTKView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { setNeedsDisplay() }
  }
}

// Layout exactly matches Phosphor.metal. One instance is an analytic capsule;
// a degenerate segment is a particle disc, optionally with a hollow center.
struct PhosphorSegment {
  var start: SIMD2<Float>
  var end: SIMD2<Float>
  var color: SIMD4<Float>
  var style: SIMD4<Float>  // radius, glow, dash period, cumulative dash offset
  var detail: SIMD4<Float>  // hollow radius, endpoint R / G / B
}

private struct PhosphorUniforms {
  var viewport: SIMD4<Float>  // width / height in points, content scale, elapsed time
  var appearance: SIMD4<Float>  // retcon tint, reduced motion, reserved
}

private enum RendererError: LocalizedError {
  case unavailable, shader, buffer
  var errorDescription: String? {
    switch self {
    case .unavailable: "Metal is unavailable on this device."
    case .shader: "Orbitals could not load its phosphor shaders."
    case .buffer: "Orbitals could not reserve its rendering buffers."
    }
  }
}

@MainActor
final class OrbitRenderer: NSObject, MTKViewDelegate {
  weak var source: (any OrbitalSceneSource)?
  /// A supplied provider switches to a transparent AR overlay. A missing frame
  /// or anchor clears the overlay instead of falling back to instrument space.
  var arProjectionProvider: (() -> ARSceneProjection?)?
  private let queue: any MTLCommandQueue
  private let tracePipeline: any MTLRenderPipelineState
  private let backgroundPipeline: any MTLRenderPipelineState
  private var buffers: [any MTLBuffer] = []
  private var bufferIndex = 0
  private let inFlight = DispatchSemaphore(value: 3)
  private let geometry = SceneGeometry()
  private static let capacity = 32_768

  static var preferredFrameRate: Int {
    let process = ProcessInfo.processInfo
    let thermallyLimited = process.thermalState == .serious || process.thermalState == .critical
    return process.isLowPowerModeEnabled || thermallyLimited ? 30 : 60
  }

  init(view: MTKView, source: any OrbitalSceneSource) throws {
    guard let device = view.device, let queue = device.makeCommandQueue() else {
      throw RendererError.unavailable
    }
    guard let library = device.makeDefaultLibrary(),
      let traceVertex = library.makeFunction(name: "phosphorVertex"),
      let traceFragment = library.makeFunction(name: "phosphorFragment"),
      let gridVertex = library.makeFunction(name: "instrumentVertex"),
      let gridFragment = library.makeFunction(name: "instrumentFragment")
    else {
      throw RendererError.shader
    }
    let traces = MTLRenderPipelineDescriptor()
    traces.label = "Orbitals · analytic phosphor capsules"
    traces.vertexFunction = traceVertex
    traces.fragmentFunction = traceFragment
    traces.colorAttachments[0].pixelFormat = view.colorPixelFormat
    traces.colorAttachments[0].isBlendingEnabled = true
    traces.colorAttachments[0].rgbBlendOperation = .add
    traces.colorAttachments[0].alphaBlendOperation = .add
    traces.colorAttachments[0].sourceRGBBlendFactor = .one
    traces.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    traces.colorAttachments[0].sourceAlphaBlendFactor = .one
    traces.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    let background = MTLRenderPipelineDescriptor()
    background.label = "Orbitals · instrument glass"
    background.vertexFunction = gridVertex
    background.fragmentFunction = gridFragment
    background.colorAttachments[0].pixelFormat = view.colorPixelFormat
    self.queue = queue
    tracePipeline = try device.makeRenderPipelineState(descriptor: traces)
    backgroundPipeline = try device.makeRenderPipelineState(descriptor: background)
    self.source = source
    super.init()
    for index in 0..<3 {
      guard
        let buffer = device.makeBuffer(
          length: Self.capacity * MemoryLayout<PhosphorSegment>.stride,
          options: .storageModeShared
        )
      else { throw RendererError.buffer }
      buffer.label = "Orbitals · frame \(index)"
      buffers.append(buffer)
    }
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    view.setNeedsDisplay()
  }

  func draw(in view: MTKView) {
    guard let window = view.window, !view.isHidden, view.bounds.width > 1,
      view.bounds.height > 1, UIApplication.shared.applicationState != .background,
      let source
    else { return }
    let frameRate = Self.preferredFrameRate
    if view.preferredFramesPerSecond != frameRate { view.preferredFramesPerSecond = frameRate }
    // The simulation and throttled instrument readouts continue while the
    // selected plot scrolls away. Avoid asking for a drawable, copying archive
    // snapshots, or rebuilding geometry when no part of the plot is visible.
    source.advanceFrame(timestamp: CACurrentMediaTime())
    let visibleRect = view.convert(view.bounds, to: window).intersection(window.bounds)
    guard !visibleRect.isNull, !visibleRect.isEmpty else { return }
    // Never block interaction waiting for the GPU. If all three buffers are in
    // flight, drop this display tick and retain the accurate simulation clock.
    guard inFlight.wait(timeout: .now()) == .success else { return }
    guard let pass = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let command = queue.makeCommandBuffer()
    else {
      inFlight.signal()
      return
    }
    let isAR = arProjectionProvider != nil
    let arProjection = arProjectionProvider?()
    if isAR {
      pass.colorAttachments[0].loadAction = .clear
      pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    }
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
      inFlight.signal()
      return
    }
    let snapshot = source.renderSnapshot()
    let bounds = view.bounds.size
    let hasGeometry = !isAR || arProjection != nil
    if hasGeometry {
      geometry.update(snapshot, size: bounds, capacity: Self.capacity, arProjection: arProjection)
    }
    let segmentCount = hasGeometry ? geometry.segments.count : 0
    let buffer = buffers[bufferIndex]
    bufferIndex = (bufferIndex + 1) % buffers.count
    if segmentCount > 0 {
      geometry.segments.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress, !bytes.isEmpty {
          buffer.contents().copyMemory(from: base, byteCount: bytes.count)
        }
      }
    }
    var uniforms = PhosphorUniforms(
      viewport: SIMD4(
        Float(bounds.width), Float(bounds.height), Float(view.contentScaleFactor),
        Float(snapshot.time)),
      appearance: SIMD4(
        snapshot.kind == .retcon ? 1 : 0, UIAccessibility.isReduceMotionEnabled ? 1 : 0, 0, 0)
    )
    encoder.label = "Orbitals · \(snapshot.kind.title)"
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<PhosphorUniforms>.stride, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PhosphorUniforms>.stride, index: 1)
    if !isAR {
      encoder.setRenderPipelineState(backgroundPipeline)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    if segmentCount > 0 {
      encoder.setRenderPipelineState(tracePipeline)
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)
      encoder.drawPrimitives(
        type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: segmentCount)
    }
    encoder.endEncoding()
    command.present(drawable)
    let semaphore = inFlight
    command.addCompletedHandler { _ in semaphore.signal() }
    command.commit()
  }
}
