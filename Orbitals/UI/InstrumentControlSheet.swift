import SwiftUI

/// The same controls are one tap away from the dashboard and every expanded plot.
struct InstrumentControlSheet: View {
  @Bindable var model: OrbitModel
  let destination: DashboardSheet
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var detent: PresentationDetent = .large

  var body: some View {
    NavigationStack {
      Group {
        switch destination {
        case .motion:
          ScrollView { MotionControls(model: model).padding(16) }
            .accessibilityIdentifier("motion-controls-scroll")
        case .controls:
          ScrollView { ControlsView(model: model, embedded: false).padding(16) }
            .accessibilityIdentifier("controls-scroll")
        case .notes:
          FieldNotesView()
        }
      }
      .background(OrbitTheme.background)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            OrbitalHaptics.shared.tap()
            dismiss()
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if destination == .motion {
          GlassEffectContainer(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(spacing: 10) {
                resetDials
                alignViews
              }
            } else {
              HStack(spacing: 12) {
                resetDials
                alignViews
              }
            }
          }
          .padding(12)
          .frame(maxWidth: .infinity)
          .background(OrbitTheme.background.opacity(0.96))
        }
      }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
  }

  private var title: String {
    switch destination {
    case .motion: "Motion control"
    case .controls: "Flight controls"
    case .notes: "Field notes"
    }
  }

  private var resetDials: some View {
    resetButton("Reset dials", symbol: "arrow.counterclockwise") {
      model.resetMotionControls()
    }
    .accessibilityIdentifier("motion-reset-dials")
    .accessibilityHint(
      model.linked
        ? "Restore default motion and dial values for all linked channels."
        : "Restore default motion and dial values for the selected channel.")
  }

  private var alignViews: some View {
    resetButton("Reset alignment", symbol: "viewfinder") {
      model.alignAllViews()
    }
    .accessibilityIdentifier("motion-reset-alignment")
    .accessibilityHint("Recenter all five views and restore their original rotation and zoom.")
  }
  private func resetButton(_ title: String, symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button {
      OrbitalHaptics.shared.tap()
      action()
    } label: {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(.vertical, 6)
    }
    .buttonStyle(.glass).tint(OrbitTheme.phosphor)
    .accessibilityLabel(title)
  }

}
