import ARKit
import MetalKit
import RealityKit
import SwiftUI

/// RealityKit presents the rear camera; the shared phosphor Metal renderer draws
/// world-space geometry over it. The overlay is transparent between traces.
struct OrbitalARView: UIViewRepresentable {
  let source: any OrbitalSceneSource
  let controller: OrbitARController

  final class Coordinator {
    let controller: OrbitARController
    var renderer: OrbitRenderer?

    init(controller: OrbitARController) { self.controller = controller }
  }

  func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

  func makeUIView(context: Context) -> UIView {
    let container = UIView()
    container.backgroundColor = .black
    let camera = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    camera.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableHDR]
    camera.isAccessibilityElement = false

    let traces = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    traces.backgroundColor = .clear
    traces.isOpaque = false
    traces.layer.isOpaque = false
    traces.clearColor = MTLClearColorMake(0, 0, 0, 0)
    traces.framebufferOnly = true
    traces.colorPixelFormat = .bgra8Unorm
    traces.sampleCount = 1
    traces.autoResizeDrawable = true
    traces.enableSetNeedsDisplay = false
    traces.preferredFramesPerSecond = OrbitRenderer.preferredFrameRate
    traces.isPaused = true
    traces.isUserInteractionEnabled = false
    traces.isAccessibilityElement = false

    let coaching = ARCoachingOverlayView()
    coaching.goal = .anyPlane
    coaching.activatesAutomatically = true
    for layer in [camera, traces, coaching] as [UIView] {
      layer.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(layer)
      NSLayoutConstraint.activate([
        layer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        layer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        layer.topAnchor.constraint(equalTo: container.topAnchor),
        layer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }

    let tap = UITapGestureRecognizer(
      target: controller, action: #selector(OrbitARController.tapped(_:)))
    let pinch = UIPinchGestureRecognizer(
      target: controller, action: #selector(OrbitARController.pinched(_:)))
    let rotation = UIRotationGestureRecognizer(
      target: controller, action: #selector(OrbitARController.rotated(_:)))
    tap.delegate = controller
    tap.cancelsTouchesInView = false
    pinch.delegate = controller
    rotation.delegate = controller
    for gesture in [tap, pinch, rotation] { container.addGestureRecognizer(gesture) }

    do {
      let renderer = try OrbitRenderer(view: traces, source: source)
      renderer.arProjectionProvider = { [weak controller] in controller?.projection() }
      context.coordinator.renderer = renderer
      traces.delegate = renderer
      controller.attach(arView: camera, metalView: traces, source: source, coachingView: coaching)
    } catch {
      Task { @MainActor in controller.renderingFailed(error.localizedDescription) }
    }
    return container
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.renderer?.source = source
  }

  static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
    coordinator.controller.detach()
    for case let metal as MTKView in view.subviews {
      metal.isPaused = true
      metal.delegate = nil
      metal.releaseDrawables()
    }
    coordinator.renderer?.arProjectionProvider = nil
    coordinator.renderer = nil
  }
}
