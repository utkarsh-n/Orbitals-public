import SwiftUI

@main
struct OrbitalsApp: App {
  @State private var model = OrbitModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      DashboardView(model: model)
        .preferredColorScheme(.dark)
        .tint(OrbitTheme.phosphor)
        .onChange(of: scenePhase) { _, phase in
          model.setActive(phase == .active)
          if phase != .active {
            OrbitalHaptics.shared.stop()
            model.save()
          }
        }
    }
  }
}
