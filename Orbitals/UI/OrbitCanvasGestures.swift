import Foundation
import SwiftUI
import UIKit

/// A transparent touch surface above Metal. Accessibility stays with its SwiftUI
/// host, where the same actions are available without multi-touch gestures.
struct OrbitCanvasGestures: UIViewRepresentable {
  let model: OrbitModel
  var panWithOneFinger = false

  func makeCoordinator() -> Coordinator {
    Coordinator(model: model, panWithOneFinger: panWithOneFinger)
  }

  func makeUIView(context: Context) -> UIView {
    let surface = UIView()
    surface.backgroundColor = .clear
    surface.isOpaque = false
    surface.isMultipleTouchEnabled = true
    surface.isAccessibilityElement = false
    surface.accessibilityElementsHidden = true
    context.coordinator.install(on: surface)
    return surface
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.update(model: model, panWithOneFinger: panWithOneFinger)
  }

  static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
    coordinator.cancel()
    for recognizer in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(recognizer) }
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private var model: OrbitModel
    private var panWithOneFinger: Bool
    private var selectedView: OrbitalViewKind
    private weak var surface: UIView?
    private weak var pan: UIPanGestureRecognizer?
    private weak var pinch: UIPinchGestureRecognizer?
    private var previousTouchCount = 0
    private var multitouchSequence = false
    private var pinchLocation: CGPoint?
    private var adjustments: Set<Adjustment> = []

    private enum Adjustment: Hashable { case pan, pinch }

    init(model: OrbitModel, panWithOneFinger: Bool) {
      self.model = model
      self.panWithOneFinger = panWithOneFinger
      selectedView = model.selectedView
    }

    func install(on view: UIView) {
      surface = view
      // One pan recognizer can transition to two fingers without a competing
      // one-finger recognizer preventing pinch from beginning.
      let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
      pan.minimumNumberOfTouches = 1
      pan.maximumNumberOfTouches = 2
      pan.delegate = self
      let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
      pinch.delegate = self
      let reset = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
      reset.numberOfTapsRequired = 2
      reset.numberOfTouchesRequired = 1
      reset.delegate = self
      view.addGestureRecognizer(pan)
      view.addGestureRecognizer(pinch)
      view.addGestureRecognizer(reset)
      self.pan = pan
      self.pinch = pinch
    }

    func update(model: OrbitModel, panWithOneFinger: Bool) {
      if self.model !== model || selectedView != model.selectedView { cancel() }
      self.model = model
      self.panWithOneFinger = panWithOneFinger
      selectedView = model.selectedView
    }

    func cancel() {
      for recognizer in surface?.gestureRecognizers ?? [] {
        recognizer.isEnabled = false
        recognizer.isEnabled = true
      }
      if !adjustments.isEmpty { OrbitalHaptics.shared.endAdjustment() }
      adjustments.removeAll()
      previousTouchCount = 0
      multitouchSequence = false
      pinchLocation = nil
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      (gestureRecognizer === pan && otherGestureRecognizer === pinch)
        || (gestureRecognizer === pinch && otherGestureRecognizer === pan)
    }

    private var pinching: Bool {
      pinch?.state == .began || pinch?.state == .changed
    }

    private func begin(_ adjustment: Adjustment) {
      if adjustments.isEmpty { OrbitalHaptics.shared.beginAdjustment() }
      adjustments.insert(adjustment)
    }

    private func end(_ adjustment: Adjustment) {
      guard adjustments.remove(adjustment) != nil else { return }
      if adjustments.isEmpty { OrbitalHaptics.shared.endAdjustment() }
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
      guard let surface, surface.bounds.width > 0, surface.bounds.height > 0 else { return }
      switch recognizer.state {
      case .began:
        begin(.pan)
        previousTouchCount = recognizer.numberOfTouches
        multitouchSequence = previousTouchCount > 1 || pinching
        recognizer.setTranslation(.zero, in: surface)
      case .changed:
        let count = recognizer.numberOfTouches
        let delta = recognizer.translation(in: surface)
        recognizer.setTranslation(.zero, in: surface)
        if count > 1 { multitouchSequence = true }
        // Adding/removing a finger shifts UIPan's centroid. Rebase that event,
        // and never resume rotation with a leftover finger after a pinch.
        guard count == previousTouchCount else {
          previousTouchCount = count
          return
        }
        guard !pinching else { return }
        if count == 2 || (count == 1 && panWithOneFinger && !multitouchSequence) {
          translate(delta, in: surface)
        } else if count == 1 && !multitouchSequence {
          let yaw = model.camera.yaw + Double(delta.x) * 0.45
          let pitch = model.camera.pitch - Double(delta.y) * 0.45
          model.setCamera(yaw: yaw, pitch: pitch)
          let normalized =
            abs(delta.x) >= abs(delta.y)
            ? (model.camera.yaw + 180) / 360 : (model.camera.pitch + 85) / 170
          OrbitalHaptics.shared.detent(normalized: normalized)
        }
      case .ended, .cancelled, .failed:
        recognizer.setTranslation(.zero, in: surface)
        previousTouchCount = 0
        multitouchSequence = pinching
        end(.pan)
      default:
        break
      }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
      guard let surface, surface.bounds.width > 0, surface.bounds.height > 0 else { return }
      switch recognizer.state {
      case .began:
        begin(.pinch)
        multitouchSequence = true
        pinchLocation = recognizer.location(in: surface)
        pan?.setTranslation(.zero, in: surface)
        zoom(recognizer, in: surface)
      case .changed:
        zoom(recognizer, in: surface)
      case .ended:
        // Once a finger lifts, location(in:) may become the remaining finger,
        // not the last pinch centroid. Never apply that discontinuity as pan.
        recognizer.scale = 1
        pan?.setTranslation(.zero, in: surface)
        pinchLocation = nil
        end(.pinch)
      case .cancelled, .failed:
        recognizer.scale = 1
        pan?.setTranslation(.zero, in: surface)
        pinchLocation = nil
        end(.pinch)
      default:
        break
      }
    }

    private func zoom(_ recognizer: UIPinchGestureRecognizer, in surface: UIView) {
      let location = recognizer.location(in: surface)
      if let previous = pinchLocation {
        // Translate before zoom so the same world point stays under the moving
        // focal centroid. The simultaneous pan callback is suppressed above.
        model.panCamera(
          dx: Double((location.x - previous.x) / surface.bounds.width),
          dy: Double((location.y - previous.y) / surface.bounds.height))
      }
      let anchor = SIMD2(
        Double(location.x / surface.bounds.width) - 0.5,
        Double(location.y / surface.bounds.height) - 0.48)
      model.zoomCamera(by: Double(recognizer.scale), anchor: anchor)
      recognizer.scale = 1
      pinchLocation = location
      pan?.setTranslation(.zero, in: surface)
      let normalized = log(model.camera.zoom / 0.25) / log(6 / 0.25)
      OrbitalHaptics.shared.detent(normalized: normalized)
    }

    private func translate(_ delta: CGPoint, in surface: UIView) {
      model.panCamera(
        dx: Double(delta.x / surface.bounds.width), dy: Double(delta.y / surface.bounds.height))
      let displacement = abs(delta.x) >= abs(delta.y) ? model.camera.panX : model.camera.panY
      OrbitalHaptics.shared.detent(normalized: (displacement + 1.5) / 3)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      model.resetCamera()
      OrbitalHaptics.shared.tap()
    }
  }
}
