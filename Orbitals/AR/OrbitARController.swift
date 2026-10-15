import ARKit
import AVFoundation
import MetalKit
import Observation
import RealityKit
import UIKit
import simd

/// One live AR session, owned by the full-screen AR presentation. The session's
/// tracking frames supply camera poses; the existing Metal renderer is the only
/// simulation clock. No camera images, maps, or world anchors are saved.
@Observable @MainActor
final class OrbitARController: NSObject {
  enum Phase: Equatable {
    case requestingPermission, scanning, ready, placed, interrupted, relocalizing, paused
    case denied, unsupported
    case failed(String)
  }

  private(set) var phase: Phase = .requestingPermission
  private(set) var isPlaced = false
  private(set) var isPlacementMode = true
  private(set) var canPlace = false
  private(set) var isCoaching = false
  private(set) var sizeMeters: Double = 0.65

  var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
  var isCameraDenied: Bool { phase == .denied }
  var scalePercent: Int { Int((sizeMeters / 0.65 * 100).rounded()) }

  var title: String {
    switch phase {
    case .requestingPermission: "Camera access"
    case .scanning: "Find a surface"
    case .ready: "Ready to anchor"
    case .placed: "Anchored in your space"
    case .interrupted: "AR interrupted"
    case .relocalizing: "Finding your anchor"
    case .paused: "AR paused"
    case .denied: "Camera access is off"
    case .unsupported: "AR requires a supported device"
    case .failed: "AR needs a fresh start"
    }
  }

  var instruction: String {
    switch phase {
    case .requestingPermission:
      "Allow camera access to place a live orbital in your space."
    case .scanning:
      "Move your iPhone slowly over a textured table, floor or wall."
    case .ready:
      "Aim the center at a surface and tap Place, or tap the surface itself."
    case .placed:
      "Walk around your orbital. Pinch to resize and twist with two fingers to rotate."
    case .interrupted:
      "The camera is temporarily unavailable. Your anchor is kept for recovery."
    case .relocalizing:
      "Point the camera at the original area. Reset placement if the room has changed."
    case .paused:
      "Return to Orbitals to resume camera tracking."
    case .denied:
      "Enable Camera for Orbitals in Settings, then return here."
    case .unsupported:
      "World tracking is available on supported iPhones and iPads, not in Simulator."
    case .failed(let message):
      message
    }
  }

  @ObservationIgnored private weak var arView: ARView?
  @ObservationIgnored private weak var metalView: MTKView?
  @ObservationIgnored private weak var source: (any OrbitalSceneSource)?
  @ObservationIgnored private weak var coachingView: ARCoachingOverlayView?
  @ObservationIgnored private var anchorID: UUID?
  @ObservationIgnored private var anchorTransform: simd_float4x4?
  @ObservationIgnored private var desiredActive = true
  @ObservationIgnored private var isRunning = false
  @ObservationIgnored private var cameraAuthorized = false
  @ObservationIgnored private var requestingCamera = false
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var lastSurfaceCheck = -Double.infinity
  @ObservationIgnored private var rotation: Float = 0
  @ObservationIgnored private var pinchStart = 0.65
  @ObservationIgnored private var rotationStart: Float = 0

  func requestCameraAccess() async {
    guard !disposed, !requestingCamera else { return }
    guard isSupported else {
      phase = .unsupported
      return
    }
    let authorized: Bool
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: authorized = true
    case .notDetermined:
      phase = .requestingPermission
      requestingCamera = true
      authorized = await AVCaptureDevice.requestAccess(for: .video)
      requestingCamera = false
    default: authorized = false
    }
    guard !disposed, !Task.isCancelled else { return }
    cameraAuthorized = authorized
    if authorized {
      if phase == .denied { phase = .scanning }
      startSessionIfPossible()
    } else {
      phase = .denied
    }
  }

  func setActive(_ active: Bool) {
    guard !disposed else { return }
    desiredActive = active
    if active {
      // Permission can change in Settings while this presentation is retained.
      cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
      startSessionIfPossible()
    } else if isRunning {
      arView?.session.pause()
      metalView?.isPaused = true
      isRunning = false
      canPlace = false
      phase = .paused
    }
  }

  func placeAtCenter() {
    guard let view = arView else { return }
    place(at: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
  }

  /// Keep the existing placement visible until another surface is chosen.
  func replace() {
    guard isRunning else { return }
    isPlacementMode = true
    canPlace = false
    lastSurfaceCheck = -.infinity
    phase = .scanning
    OrbitalHaptics.shared.tap()
  }

  /// Also provides a recovery path if relocalization cannot recover the room.
  func resetPlacement() {
    anchorID = nil
    anchorTransform = nil
    isPlaced = false
    isPlacementMode = true
    canPlace = false
    rotation = 0
    sizeMeters = 0.65
    lastSurfaceCheck = -.infinity
    OrbitalHaptics.shared.tap()
    guard cameraAuthorized, desiredActive, !disposed, let view = arView else { return }
    phase = .scanning
    view.session.run(configuration(), options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
    metalView?.isPaused = false
    coachingView?.setActive(true, animated: true)
  }

  func scale(by multiplier: Double) {
    guard isPlaced, multiplier.isFinite, multiplier > 0 else { return }
    sizeMeters = min(2, max(0.15, sizeMeters * multiplier))
    OrbitalHaptics.shared.selection()
  }

  func resetScale() {
    sizeMeters = 0.65
    rotation = 0
    OrbitalHaptics.shared.tap()
  }

  func shutdown() {
    guard !disposed else { return }
    disposed = true
    desiredActive = false
    detach()
  }

  /// SwiftUI may remove the camera host after permission is denied and recreate
  /// it after a Settings change. Only dismissal permanently disposes the owner.
  func detach() {
    isRunning = false
    metalView?.isPaused = true
    arView?.session.pause()
    arView?.session.delegate = nil
    coachingView?.session = nil
    coachingView?.delegate = nil
    anchorID = nil
    anchorTransform = nil
    isPlaced = false
    isPlacementMode = true
    isCoaching = false
    canPlace = false
    arView = nil
    metalView = nil
    source = nil
    coachingView = nil
  }

  func attach(
    arView: ARView, metalView: MTKView, source: any OrbitalSceneSource,
    coachingView: ARCoachingOverlayView
  ) {
    guard !disposed else { return }
    self.arView = arView
    self.metalView = metalView
    self.source = source
    self.coachingView = coachingView
    arView.session.delegateQueue = .main
    arView.session.delegate = self
    coachingView.session = arView.session
    coachingView.delegate = self
    startSessionIfPossible()
  }

  func renderingFailed(_ message: String) {
    arView?.session.pause()
    metalView?.isPaused = true
    isRunning = false
    phase = .failed(message)
  }

  /// Called from the Metal display tick, including when the simulation is paused.
  /// Use the latest corrected anchor pose, not a frozen raycast transform.
  func projection() -> ARSceneProjection? {
    guard isRunning, phase != .interrupted, phase != .relocalizing,
      let view = arView, let frame = view.session.currentFrame,
      let anchorID, let source, view.bounds.width > 1, view.bounds.height > 1
    else { return nil }
    if let updated = frame.anchors.first(where: { $0.identifier == anchorID }) {
      anchorTransform = updated.transform
    }
    guard let anchorTransform else { return nil }
    let snapshot = source.renderSnapshot()
    let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    let camera = frame.camera
    let viewProjection =
      camera.projectionMatrix(
        for: orientation, viewportSize: view.bounds.size, zNear: 0.01, zFar: 100
      ) * camera.viewMatrix(for: orientation)
    return ARSceneProjection(
      viewProjection: viewProjection,
      modelTransform: ARPlacementMath.transform(
        anchor: anchorTransform, kind: snapshot.kind, settings: snapshot.settings,
        sizeMeters: sizeMeters, yaw: rotation))
  }

  private func configuration() -> ARWorldTrackingConfiguration {
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.worldAlignment = .gravity
    // The visualization is emissive; environment probes, mesh reconstruction,
    // scene depth and people occlusion are unnecessary for this renderer.
    configuration.environmentTexturing = .none
    configuration.isLightEstimationEnabled = false
    return configuration
  }

  private func startSessionIfPossible() {
    guard !disposed, isSupported, cameraAuthorized, desiredActive, !isRunning,
      let view = arView
    else { return }
    view.session.run(configuration())
    isRunning = true
    metalView?.isPaused = false
    phase = isPlaced ? .relocalizing : .scanning
    lastSurfaceCheck = -.infinity
  }

  private func place(at point: CGPoint) {
    guard isRunning, isPlacementMode, let view = arView,
      let frame = view.session.currentFrame, case .normal = frame.camera.trackingState,
      let result = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any)
        .first
    else {
      OrbitalHaptics.shared.boundary()
      return
    }
    if let anchorID,
      let old = view.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID })
    {
      view.session.remove(anchor: old)
    }
    let anchor = ARAnchor(name: "Orbitals placement", transform: result.worldTransform)
    anchorID = anchor.identifier
    anchorTransform = anchor.transform
    view.session.add(anchor: anchor)
    isPlaced = true
    isPlacementMode = false
    canPlace = false
    phase = .placed
    coachingView?.setActive(false, animated: true)
    OrbitalHaptics.shared.success()
  }

  @objc func tapped(_ gesture: UITapGestureRecognizer) {
    guard let view = arView, !isCoaching, isPlacementMode else { return }
    place(at: gesture.location(in: view))
  }

  @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
    guard isPlaced, !isPlacementMode, !isCoaching else { return }
    switch gesture.state {
    case .began:
      pinchStart = sizeMeters
      OrbitalHaptics.shared.beginAdjustment()
    case .changed:
      sizeMeters = min(2, max(0.15, pinchStart * Double(gesture.scale)))
      OrbitalHaptics.shared.detent(normalized: (sizeMeters - 0.15) / 1.85)
    case .ended, .cancelled, .failed:
      OrbitalHaptics.shared.endAdjustment()
    default: break
    }
  }

  @objc func rotated(_ gesture: UIRotationGestureRecognizer) {
    guard isPlaced, !isPlacementMode, !isCoaching else { return }
    switch gesture.state {
    case .began:
      rotationStart = rotation
      OrbitalHaptics.shared.beginAdjustment()
    case .changed:
      rotation = rotationStart - Float(gesture.rotation)
      let turns = Double(rotation) / (.pi * 2)
      OrbitalHaptics.shared.detent(normalized: turns - floor(turns))
    case .ended, .cancelled, .failed:
      OrbitalHaptics.shared.endAdjustment()
    default: break
    }
  }
}

// ARSession explicitly delivers every callback on DispatchQueue.main. The
// preconcurrency conformance bridges the Objective-C delegate's old annotations.
extension OrbitARController: @preconcurrency ARSessionDelegate {
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard isRunning, !disposed else { return }
    if let anchorID, let anchor = frame.anchors.first(where: { $0.identifier == anchorID }) {
      anchorTransform = anchor.transform
    }
    switch frame.camera.trackingState {
    case .normal:
      if isPlacementMode {
        if frame.timestamp - lastSurfaceCheck >= 0.12, let view = arView {
          lastSurfaceCheck = frame.timestamp
          let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
          let available = !view.raycast(
            from: center, allowing: .existingPlaneGeometry, alignment: .any
          ).isEmpty
          if canPlace != available { canPlace = available }
          let next: Phase = available ? .ready : .scanning
          if phase != next { phase = next }
        }
      } else if phase != .placed {
        phase = .placed
      }
    case .limited(.relocalizing):
      if phase != .relocalizing { phase = .relocalizing }
      canPlace = false
    case .limited, .notAvailable:
      if phase != .scanning { phase = .scanning }
      canPlace = false
    @unknown default:
      if phase != .scanning { phase = .scanning }
      canPlace = false
    }
  }

  func sessionWasInterrupted(_ session: ARSession) {
    guard !disposed, desiredActive else { return }
    // ARKit pauses itself here. Calling pause would prevent its ended callback.
    phase = .interrupted
    canPlace = false
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    guard !disposed, desiredActive else { return }
    phase = isPlaced ? .relocalizing : .scanning
    lastSurfaceCheck = -.infinity
  }

  func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

  func session(_ session: ARSession, didFailWithError error: any Error) {
    guard !disposed else { return }
    isRunning = false
    canPlace = false
    metalView?.isPaused = true
    phase = .failed(error.localizedDescription)
  }
}

extension OrbitARController: @preconcurrency ARCoachingOverlayViewDelegate {
  func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
    isCoaching = true
  }

  func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
    isCoaching = false
    lastSurfaceCheck = -.infinity
  }

  func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
    resetPlacement()
  }
}

extension OrbitARController: UIGestureRecognizerDelegate {
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    // Native coaching controls must receive their touches, including Start Over
    // during relocalization. Placement taps have no role after anchoring.
    guard !isCoaching, isRunning else { return false }
    if gestureRecognizer is UITapGestureRecognizer { return isPlacementMode }
    return isPlaced && !isPlacementMode
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    (gestureRecognizer is UIPinchGestureRecognizer
      && otherGestureRecognizer is UIRotationGestureRecognizer)
      || (gestureRecognizer is UIRotationGestureRecognizer
        && otherGestureRecognizer is UIPinchGestureRecognizer)
  }
}
