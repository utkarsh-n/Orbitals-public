import SwiftUI

enum DashboardSheet: String, Identifiable {
  case motion, controls, notes
  var id: String { rawValue }
}

struct DashboardView: View {
  @Bindable var model: OrbitModel
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var sheet: DashboardSheet?
  @State private var expandedView: OrbitalViewKind?
  @State private var fullScreenActive = false

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            introduction
            dimensionSelector
            if geometry.size.width > 850 {
              HStack(alignment: .top, spacing: 20) {
                primaryColumn(width: geometry.size.width * 0.60)
                ControlsView(model: model, embedded: true).frame(maxWidth: 400)
              }
            } else {
              primaryColumn(width: geometry.size.width - 32)
            }
          }
          .padding(.horizontal, geometry.size.width > 850 ? 26 : 16)
          .padding(.top, 8).padding(.bottom, 20)
          .frame(maxWidth: 1500).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("dashboard-scroll")
        .background(OrbitTheme.background)
      }
      .navigationTitle("Orbitals")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            OrbitalHaptics.shared.tap()
            sheet = .motion
          } label: {
            Label("Dials", systemImage: "dial.medium")
              .labelStyle(.titleAndIcon)
          }
          .accessibilityLabel("Motion control")
          .accessibilityIdentifier("motion-controls-open")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            OrbitalHaptics.shared.tap()
            sheet = .notes
          } label: {
            Image(systemName: "info")
          }
          .accessibilityLabel("Field notes")
          Button {
            OrbitalHaptics.shared.tap()
            sheet = .controls
          } label: {
            Image(systemName: "slider.horizontal.3")
          }
          .accessibilityLabel("All controls")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { transport }
      .fullScreenCover(item: $expandedView) { _ in
        FullScreenVisualization(model: model)
          .onAppear { fullScreenActive = true }
          .onDisappear {
            fullScreenActive = false
            model.invalidate()
          }
      }
      .sheet(item: $sheet) { destination in
        InstrumentControlSheet(model: model, destination: destination)
      }
      .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.selectedView)
      .onKeyPress(.space) {
        OrbitalHaptics.shared.tap()
        model.running.toggle()
        return .handled
      }
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Circle().fill(OrbitTheme.phosphor).frame(width: 5, height: 5)
        Text("SPACE AGE ORBITAL DYNAMICS").tracking(2)
      }.font(.system(.caption2, design: .monospaced)).foregroundStyle(OrbitTheme.muted)
      Text("Decomposing the frequencies.").font(.subheadline).foregroundStyle(.white.opacity(0.8))
    }
  }

  private var dimensionSelector: some View {
    Picker(
      "Dimension",
      selection: Binding(
        get: { model.dimension },
        set: {
          OrbitalHaptics.shared.selection()
          model.setDimension($0)
        })
    ) {
      Text("2D").tag(2)
      Text("3D").tag(3)
      Text("4D").tag(4)
      Text("5D").tag(5)
    }.pickerStyle(.segmented).accessibilityIdentifier("dimension-picker")
  }

  @ViewBuilder private func primaryColumn(width: CGFloat) -> some View {
    VStack(spacing: 18) {
      if model.dimension == 5 { viewSelector }
      VisualizationPanel(
        model: model, width: width,
        isRendering: expandedView == nil && !fullScreenActive,
        onExpand: { expandedView = model.selectedView })
      if model.selectedView == .cylinder || model.selectedView == .torus {
        TimelineInspector(model: model)
      }
      if model.selectedView == .tracks { LoopControls(model: model) }
      if model.selectedView == .retcon { RetconControls(model: model) }
      ActionButton(title: "Motion control & harmonics", symbol: "dial.medium") {
        sheet = .motion
      }
      .frame(maxWidth: .infinity)
      TelemetryPanel(model: model)
      if sizeClass == .compact {
        ActionButton(title: "Geometry, display & haptics", symbol: "slider.horizontal.3") {
          sheet = .controls
        }
        .frame(maxWidth: .infinity)
      }
      Text("4D space is projected. 5D adds simulation time.")
        .font(.caption).foregroundStyle(OrbitTheme.muted).frame(maxWidth: .infinity)
    }.frame(maxWidth: .infinity)
  }

  private var viewSelector: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        GlassEffectContainer(spacing: 12) {
          HStack(spacing: 10) {
            ForEach(OrbitalViewKind.allCases) { kind in
              Button {
                OrbitalHaptics.shared.selection()
                model.chooseView(kind)
              } label: {
                Label(kind.title, systemImage: kind.symbol).font(.subheadline.weight(.medium))
                  .padding(.vertical, 6)
              }
              .buttonStyle(.glass).tint(model.selectedView == kind ? OrbitTheme.phosphor : .white)
              .accessibilityAddTraits(model.selectedView == kind ? .isSelected : [])
              .accessibilityIdentifier("view-\(kind.rawValue)")
              .id(kind)
            }
          }.padding(.vertical, 4)
        }
      }.scrollIndicators(.hidden).accessibilityIdentifier("view-selector")
        .onAppear { proxy.scrollTo(model.selectedView, anchor: .center) }
        .onChange(of: model.selectedView) { _, view in
          withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            proxy.scrollTo(view, anchor: .center)
          }
        }
    }
  }

  private var transport: some View {
    GlassEffectContainer(spacing: 10) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 6) {
          ClockReadout(model: model)
          HStack(spacing: 16) {
            ActionButton(
              title: model.running ? "Pause" : "Play",
              symbol: model.running ? "pause.fill" : "play.fill", prominent: true
            ) { model.running.toggle() }
            .labelStyle(.iconOnly).accessibilityIdentifier("transport-play")
            ActionButton(title: "Step", symbol: "forward.end") { model.step() }.labelStyle(
              .iconOnly
            ).accessibilityIdentifier("transport-step")
            experimentActions
          }
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
      } else {
        HStack(spacing: 10) {
          ActionButton(
            title: model.running ? "Pause" : "Play",
            symbol: model.running ? "pause.fill" : "play.fill", prominent: true
          ) { model.running.toggle() }
          .accessibilityIdentifier("transport-play")
          ActionButton(title: "Step", symbol: "forward.end") { model.step() }
            .accessibilityIdentifier("transport-step")
          experimentActions
          Spacer(minLength: 0)
          ClockReadout(model: model)
        }.padding(.horizontal, 16).padding(.vertical, 10)
      }
    }
    .background {
      LinearGradient(
        colors: [.clear, OrbitTheme.background.opacity(0.96)], startPoint: .top, endPoint: .bottom
      ).ignoresSafeArea(edges: .bottom)
    }
  }

  private var experimentActions: some View {
    Menu {
      Button("Clear trails", systemImage: "eraser") {
        OrbitalHaptics.shared.tap()
        model.clearTrails()
      }
      Button("Clear recorded history", systemImage: "clock.badge.xmark") {
        OrbitalHaptics.shared.tap()
        model.clearHistory()
      }
      Divider()
      Button("Reset experiment", systemImage: "arrow.counterclockwise") {
        OrbitalHaptics.shared.success()
        model.reset()
      }
    } label: {
      Image(systemName: "ellipsis").frame(width: 44, height: 44)
    }
    .buttonStyle(.glass).accessibilityLabel("Experiment actions")
    .simultaneousGesture(TapGesture().onEnded { OrbitalHaptics.shared.tap() })
  }
}

private struct ClockReadout: View {
  let model: OrbitModel
  var body: some View {
    VStack(alignment: .trailing, spacing: 3) {
      Text(model.running ? "RUN" : "HOLD").font(.system(.caption2, design: .monospaced))
        .foregroundStyle(model.running ? OrbitTheme.phosphor : OrbitTheme.amber)
      Text(model.clock).font(.system(.caption, design: .monospaced)).monospacedDigit()
        .foregroundStyle(OrbitTheme.amber)
    }.accessibilityElement(children: .combine).accessibilityLabel(
      "Simulation \(model.running ? "running" : "paused"), \(model.clock)")
  }
}
