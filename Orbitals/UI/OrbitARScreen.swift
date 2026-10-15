import SwiftUI

/// Live AR owns the only active plot renderer while the full-screen canvas is covered.
struct OrbitARScreen: View {
  @Bindable var model: OrbitModel
  @State private var controller = OrbitARController()
  @State private var sheet: DashboardSheet?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if controller.isSupported && !controller.isCameraDenied {
        OrbitalARView(source: model, controller: controller).ignoresSafeArea()
          .accessibilityHidden(true)
      }
      if !controller.isSupported || controller.isCameraDenied {
        ContentUnavailableView {
          Label(controller.title, systemImage: controller.isCameraDenied ? "camera.fill" : "arkit")
        } description: {
          Text(controller.instruction)
        } actions: {
          if controller.isCameraDenied {
            Button("Open Settings") {
              OrbitalHaptics.shared.tap()
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            }
            .buttonStyle(.glassProminent).tint(OrbitTheme.phosphor)
            .accessibilityIdentifier("ar-open-settings")
          }
        }
        .accessibilityIdentifier("ar-unavailable")
      }
      if controller.isSupported && controller.isPlacementMode && !controller.isCoaching
        && !controller.isCameraDenied && !sessionFailed
      {
        Image(systemName: "scope")
          .font(.system(size: 34, weight: .light))
          .foregroundStyle(controller.canPlace ? OrbitTheme.phosphor : .white.opacity(0.7))
          .shadow(color: .black.opacity(0.7), radius: 4)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      VStack(spacing: 12) {
        header
        Spacer(minLength: 0)
        if controller.isSupported && !controller.isCameraDenied {
          instructions
          if !controller.isCoaching || sessionFailed { actions }
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .statusBarHidden()
    .sheet(item: $sheet) { destination in
      InstrumentControlSheet(model: model, destination: destination)
    }
    .task {
      controller.setActive(scenePhase == .active)
      await controller.requestCameraAccess()
    }
    .onChange(of: scenePhase) { _, phase in
      controller.setActive(phase == .active)
      if phase == .active {
        Task { await controller.requestCameraAccess() }
      }
    }
    .onDisappear {
      controller.shutdown()
      model.invalidate()
    }
    .onKeyPress(.escape) {
      close()
      return .handled
    }
  }

  private var header: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) {
        iconButton("Motion control", symbol: "dial.medium", id: "ar-motion-controls") {
          sheet = .motion
        }
        Menu {
          ForEach(OrbitalViewKind.allCases) { view in
            Button {
              OrbitalHaptics.shared.selection()
              model.chooseView(view)
            } label: {
              Label(view.title, systemImage: model.selectedView == view ? "checkmark" : view.symbol)
            }
          }
        } label: {
          Label(model.selectedView.title, systemImage: "arkit")
            .font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .buttonStyle(.glass).controlSize(.large)
        .accessibilityLabel("AR visualization")
        .accessibilityIdentifier("ar-view-picker")
        .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
        Spacer(minLength: 0)
        iconButton("Close AR", symbol: "xmark", id: "ar-close", action: close)
      }
    }
  }

  private var sessionFailed: Bool {
    if case .failed = controller.phase { return true }
    return false
  }

  private var instructions: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Circle().fill(controller.isPlaced ? OrbitTheme.phosphor : .white)
          .frame(width: 6, height: 6)
        Text(controller.title).font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("ar-status")
        Spacer(minLength: 0)
        if controller.isPlaced {
          Text("\(controller.scalePercent)%").monospacedDigit().font(.caption)
        }
      }
      if verticalSizeClass != .compact || !controller.isPlaced {
        Text(controller.instruction).font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14).frame(maxWidth: 540)
    .glassEffect(.regular, in: .rect(cornerRadius: 22))
    .accessibilityElement(children: .contain)
  }

  private var actions: some View {
    GlassEffectContainer(spacing: 10) {
      VStack(spacing: 10) {
        if dynamicTypeSize.isAccessibilitySize {
          placementAction
          playbackAndSize
        } else {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
              placementAction
              playbackAndSize
            }
            VStack(spacing: 10) {
              placementAction
              playbackAndSize
            }
          }
        }
      }
      .frame(maxWidth: 540)
    }
  }

  private var placementAction: some View {
    Button {
      if controller.isPlacementMode { controller.placeAtCenter() } else { controller.replace() }
    } label: {
      Label(controller.isPlacementMode ? "Place here" : "Move anchor", systemImage: "scope")
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 30)
    }
    .buttonStyle(.glassProminent).tint(.white).controlSize(.large)
    .disabled(controller.isPlacementMode && !controller.canPlace)
    .accessibilityIdentifier("ar-place")
  }

  private var playbackAndSize: some View {
    HStack(spacing: 10) {
      iconButton(
        model.running ? "Pause" : "Play",
        symbol: model.running ? "pause.fill" : "play.fill", id: "ar-play"
      ) {
        model.running.toggle()
      }
      iconButton("Smaller", symbol: "minus.magnifyingglass", id: "ar-smaller") {
        controller.scale(by: 0.8)
      }.disabled(!controller.isPlaced)
      iconButton("Larger", symbol: "plus.magnifyingglass", id: "ar-larger") {
        controller.scale(by: 1.25)
      }.disabled(!controller.isPlaced)
      Menu {
        Button("Reset size and rotation", systemImage: "arrow.counterclockwise") {
          OrbitalHaptics.shared.tap()
          controller.resetScale()
        }.disabled(!controller.isPlaced)
        Button("Scan a new space", systemImage: "viewfinder") {
          OrbitalHaptics.shared.tap()
          controller.resetPlacement()
        }
      } label: {
        Image(systemName: "ellipsis").frame(minWidth: 18, minHeight: 22)
      }
      .buttonStyle(.glass).controlSize(.large)
      .accessibilityLabel("AR placement actions")
      .accessibilityIdentifier("ar-actions")
      .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
    }
  }

  private func iconButton(
    _ title: String, symbol: String, id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      OrbitalHaptics.shared.tap()
      action()
    } label: {
      Image(systemName: symbol).frame(minWidth: 18, minHeight: 22)
    }
    .buttonStyle(.glass).controlSize(.large)
    .accessibilityLabel(title).accessibilityIdentifier(id)
  }

  private func close() { dismiss() }
}
