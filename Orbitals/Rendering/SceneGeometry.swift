import CoreGraphics
import Foundation
import simd

/// Converts only the selected instrument to bounded, reusable GPU instances.
/// Physics stays in Core; all finite-window joins here are display geometry.
final class SceneGeometry {
  private(set) var segments: [PhosphorSegment] = []
  private var snapshot: RenderSnapshot!
  private var size = CGSize.zero
  private var scale = 1.0
  private var arProjection: ARSceneProjection?
  private var limit = 32_768
  private var meshKey: MeshShape?
  private var mesh: [[Vec4]] = []
  private var trajectoryKey: TrackShapeSignature?
  private var trajectories: [[Vec4]] = []
  private var trackKey: TrackShapeSignature?
  private var tracks: [[Vec3]] = []
  private let tau = Double.pi * 2

  private let green = SIMD4<Float>(0.35, 0.83, 0.49, 1)
  private let ghost = SIMD4<Float>(0.55, 0.80, 0.91, 1)
  private let amber = SIMD4<Float>(1, 0.75, 0.37, 1)
  private let white = SIMD4<Float>(1, 1, 1, 1)
  private static let channelColors: [SIMD4<Float>] = [
    SIMD4(0.1, 0.93, 1, 1), SIMD4(1, 0.18, 0.78, 1), SIMD4(1, 0.91, 0.18, 1),
  ]
  private var colors: [SIMD4<Float>] { Self.channelColors }

  /// One closed CMY color cycle per path, shifted to begin at its channel's
  /// primary. Wrapping phase before interpolation makes the seam exact.
  static func cyclicTrackColor(phase: Double, channel: Int) -> SIMD4<Float> {
    let position = TrackMath.modulo(phase) * 3
    let step = Int(position)
    let start = (step + (channel % 3 + 3) % 3) % 3
    let end = (start + 1) % 3
    let fraction = Float(position - Double(step))
    return channelColors[start] + (channelColors[end] - channelColors[start]) * fraction
  }

  private struct MeshShape: Equatable {
    let radius, morph, xw, yw, zw: Double
    let fourD: Bool
    init(_ s: OrbitalSettings) {
      radius = s.radius
      morph = s.morph
      xw = s.xw
      yw = s.yw
      zw = s.zw
      fourD = s.fourD
    }
  }

  init() { segments.reserveCapacity(32_768) }

  func update(
    _ snapshot: RenderSnapshot, size: CGSize, capacity: Int,
    arProjection: ARSceneProjection? = nil
  ) {
    self.snapshot = snapshot
    self.arProjection = arProjection
    // Release the archive at frame end. Retaining yesterday's Array snapshot
    // here would force the recorder to copy its entire COW storage on append.
    defer { self.snapshot = nil }
    self.size = size
    limit = capacity
    segments.removeAll(keepingCapacity: true)
    switch snapshot.kind {
    case .spatial:
      // The 4D eye is at 3R, so projected points fit in a 1.5R sphere.
      let bound = snapshot.settings.radius * (snapshot.settings.fourD ? 1.5 : 1.1)
      scale = max(1, min(size.width - 36, size.height - 54) / (2 * bound)) * snapshot.camera.zoom
      spatial()
    case .cylinder:
      scale =
        max(
          1,
          CameraMath.cylinderScale(
            width: size.width, height: size.height,
            yaw: snapshot.camera.yaw, pitch: snapshot.camera.pitch)) * snapshot.camera.zoom
      cylinder()
    case .torus, .tracks, .retcon:
      // A rotation-invariant bound avoids pumping the apparent size on drag.
      scale =
        max(
          1,
          min(size.width - 32, size.height - 54)
            / (2 * (TorusMath.torusRadius + TorusMath.tubeRadius))) * snapshot.camera.zoom
      if snapshot.kind == .tracks {
        orbitalTracks()
      } else {
        timeTorus(retcon: snapshot.kind == .retcon)
      }
    }
  }

  private func faded(_ color: SIMD4<Float>, _ alpha: Double) -> SIMD4<Float> {
    SIMD4(color.x, color.y, color.z, Float(max(0, min(1, alpha))))
  }

  private func screen(_ point: Vec3) -> SIMD2<Float>? {
    if let arProjection { return arProjection.project(point, viewport: size) }
    let v = CameraMath.rotate(point, yaw: snapshot.camera.yaw, pitch: snapshot.camera.pitch)
    return viewportPoint(v)
  }

  private func spatialScreen(_ point: Vec4) -> SIMD2<Float>? {
    var settings = snapshot.settings
    settings.yaw = arProjection == nil ? snapshot.camera.yaw : 0
    settings.pitch = arProjection == nil ? snapshot.camera.pitch : 0
    let v = OrbitalMath.project(point, settings: settings)
    if let arProjection { return arProjection.project(v, viewport: size) }
    return viewportPoint(v)
  }

  private func viewportPoint(_ point: Vec3) -> SIMD2<Float> {
    // Pan is normalized to the viewport so it survives device rotation and
    // expansion. Only geometry scales: phosphor strokes and particles stay crisp.
    SIMD2(
      Float(size.width * (0.5 + snapshot.camera.panX) + point.x * scale),
      Float(size.height * (0.48 + snapshot.camera.panY) - point.y * scale))
  }

  private func add(
    _ a: SIMD2<Float>?, _ b: SIMD2<Float>?, color: SIMD4<Float>,
    endColor: SIMD4<Float>? = nil, width: Float = 1.5,
    glow: Double = 0, dash: Float = 0, offset: Float = 0, hollow: Float = 0
  ) {
    guard let a, let b, segments.count < limit,
      a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite,
      width.isFinite, glow.isFinite, dash.isFinite, offset.isFinite, hollow.isFinite
    else {
      return
    }
    let endpoint = endColor ?? color
    segments.append(
      PhosphorSegment(
        start: a, end: b, color: color,
        style: SIMD4(width * 0.5, Float(glow), dash, offset),
        detail: SIMD4(hollow, endpoint.x, endpoint.y, endpoint.z)))
  }

  private func dot(
    _ p: SIMD2<Float>?, color: SIMD4<Float>, diameter: Float = 7, hollow: Bool = false
  ) {
    add(
      p, p, color: color, width: diameter, glow: snapshot.settings.glow,
      hollow: hollow ? max(0, diameter * 0.5 - 1.2) : 0)
  }

  private func nextDashOffset(
    _ offset: Float, from a: SIMD2<Float>?, to b: SIMD2<Float>?
  ) -> Float {
    guard let a, let b else { return 0 }
    let next = offset + simd_distance(a, b)
    return next.isFinite ? next : 0
  }

  private func path(
    _ vertices: [Vec3], color: SIMD4<Float>, width: Float = 1,
    glow: Double = 0, dash: Float = 0
  ) {
    guard let first = vertices.first else { return }
    var previous = screen(first)
    var distance: Float = 0
    for vertex in vertices.dropFirst() {
      let next = screen(vertex)
      add(previous, next, color: color, width: width, glow: glow, dash: dash, offset: distance)
      distance = nextDashOffset(distance, from: previous, to: next)
      previous = next
    }
  }

  private func gradientPath<Point>(
    _ vertices: [Point], channel: Int, alpha: Double, width: Float,
    glow: Double, dash: Float = 0, projection: (Point) -> SIMD2<Float>?
  ) {
    guard vertices.count > 1, let first = vertices.first else { return }
    let lastIndex = vertices.count - 1
    var previous = projection(first)
    var previousColor = faded(Self.cyclicTrackColor(phase: 0, channel: channel), alpha)
    var distance: Float = 0
    for index in 1...lastIndex {
      let next = projection(vertices[index])
      let nextColor = faded(
        Self.cyclicTrackColor(phase: Double(index) / Double(lastIndex), channel: channel), alpha)
      add(
        previous, next, color: previousColor, endColor: nextColor, width: width,
        glow: glow, dash: dash, offset: distance)
      distance = nextDashOffset(distance, from: previous, to: next)
      previous = next
      previousColor = nextColor
    }
  }

  private func spatial() {
    let s = snapshot.settings
    let now = snapshot.time
    if s.mesh {
      let key = MeshShape(s)
      if meshKey != key {
        mesh = OrbitalMath.meshLines(settings: s)
        meshKey = key
      }
      for line in mesh {
        guard let first = line.first else { continue }
        var previous = spatialScreen(first)
        for point in line.dropFirst() {
          let next = spatialScreen(point)
          add(previous, next, color: faded(green, 0.24), width: 0.85, glow: s.glow * 0.15)
          previous = next
        }
      }
    }
    if s.axes {
      for axis in 0..<(s.fourD ? 4 : 3) {
        var start = Vec4.zero
        var end = Vec4.zero
        start[axis] = -s.radius * 1.05
        end[axis] = s.radius * 1.05
        start = OrbitalMath.rotate4(start, settings: s)
        end = OrbitalMath.rotate4(end, settings: s)
        add(
          spatialScreen(start), spatialScreen(end), color: faded(axis == 3 ? ghost : green, 0.4),
          width: 0.9, dash: axis == 3 ? 5 : 0)
      }
    }
    if s.mesh {
      let key = TrackMath.trackShapeKey(s)
      if trajectoryKey != key {
        trajectories = s.channels.indices.map { channel in
          (0...320).map { step in
            TrackMath.cyclePoint(fraction: Double(step) / 320, index: channel, settings: s)
          }
        }
        trajectoryKey = key
      }
      // Dashed analytical guides expose the selected motion even at a shared
      // starting point. They are independent of, and never added to, the archive.
      for channel in trajectories.indices {
        gradientPath(
          trajectories[channel], channel: channel, alpha: 0.8, width: 1.4,
          glow: s.glow * 0.65, dash: 6, projection: spatialScreen)
      }
    }
    if s.trails, s.persistence > 0 {
      for channel in 0..<3 {
        var previous: TimelineSample?
        for sample in snapshot.samples {
          guard sample.t >= max(snapshot.trailCutoff, now - s.persistence), sample.t <= now else {
            previous = nil
            continue
          }
          if let last = previous, last.segment == sample.segment {
            let alpha = 0.76 * max(0, 1 - (now - sample.t) / s.persistence)
            add(
              spatialScreen(last.points[channel]), spatialScreen(sample.points[channel]),
              color: faded(colors[channel], alpha), width: 1.6, glow: s.glow * 0.5)
          }
          previous = sample
        }
      }
    }
    let current = OrbitalMath.pointsAt(now, settings: s).map(spatialScreen)
    if s.connections { connect(current) }
    for channel in 0..<3 { dot(current[channel], color: colors[channel], diameter: 8) }
  }

  private func connect(_ points: [SIMD2<Float>?]) {
    guard points.count >= 3 else { return }
    for channel in 0..<3 {
      add(
        points[channel], points[(channel + 1) % 3],
        color: colors[channel], endColor: colors[(channel + 1) % 3], width: 1.8,
        glow: snapshot.settings.glow)
    }
  }

  private func cylinderPoint(_ v: Vec4, offset: Double) -> Vec3 {
    Vec3(
      offset / max(0.01, snapshot.horizon) * 2.8,
      v[max(0, min(3, snapshot.planeIndices.x))] * 0.4,
      v[max(0, min(3, snapshot.planeIndices.y))] * 0.4)
  }

  private func cylinderRing(offset: Double) -> [Vec3] {
    (0...64).map { index in
      let a = Double(index) / 64 * tau
      return Vec3(offset / max(0.01, snapshot.horizon) * 2.8, 1.2 * cos(a), 1.2 * sin(a))
    }
  }

  private func cylinder() {
    let s = snapshot.settings
    let span = snapshot.horizon
    if s.mesh {
      for slice in -4...4 {
        path(
          cylinderRing(offset: Double(slice) * span / 4),
          color: faded(green, slice > 0 ? 0.30 : 0.2),
          dash: slice > 0 ? 7 : 0)
      }
      for index in 0..<8 {
        let a = Double(index) / 8 * tau
        path(
          [Vec3(-2.8, 1.2 * cos(a), 1.2 * sin(a)), Vec3(2.8, 1.2 * cos(a), 1.2 * sin(a))],
          color: faded(green, 0.25))
      }
    }
    if s.axes {
      path([Vec3(-2.8, 0, 0), Vec3(2.8, 0, 0)], color: faded(green, 0.35), dash: 6)
    }
    archiveTraces(snapshot.samples, projection: cylinderPoint)
    modelTraces(
      settings: s, from: snapshot.time, to: snapshot.time + span, dashed: true,
      projection: cylinderPoint)
    path(cylinderRing(offset: 0), color: white, width: 1.4, glow: s.glow)
    let current = OrbitalMath.pointsAt(snapshot.time, settings: s).map {
      screen(cylinderPoint($0, offset: 0))
    }
    if s.connections { connect(current) }
    for channel in 0..<3 { dot(current[channel], color: colors[channel]) }
    inspection(projection: cylinderPoint, ring: cylinderRing)
  }

  private func torusPoint(_ v: Vec4, offset: Double) -> Vec3 {
    TorusMath.projectToTorus(v, offset: offset, horizon: snapshot.horizon)
  }

  private func torusRing(offset: Double) -> [Vec3] {
    (0...64).map { index in
      let a = Double(index) / 64 * tau
      return TorusMath.tubePoint(
        offset: offset, horizon: snapshot.horizon,
        u: TorusMath.tubeRadius * cos(a), v: TorusMath.tubeRadius * sin(a))
    }
  }

  private lazy var torusCage: [[Vec3]] = {
    var lines: [[Vec3]] = []
    for index in 0..<8 {
      let a = Double(index) / 8 * tau
      lines.append(
        (0...128).map { step in
          TorusMath.closedTubePoint(
            phase: Double(step) / 128,
            u: TorusMath.tubeRadius * cos(a), v: TorusMath.tubeRadius * sin(a))
        })
    }
    for slice in 0..<20 {
      lines.append(
        (0...48).map { step in
          let a = Double(step) / 48 * tau
          return TorusMath.closedTubePoint(
            phase: Double(slice) / 20,
            u: TorusMath.tubeRadius * cos(a), v: TorusMath.tubeRadius * sin(a))
        })
    }
    return lines
  }()

  private func cage(retcon: Bool = false) {
    if snapshot.settings.mesh {
      for line in torusCage { path(line, color: faded(retcon ? ghost : green, 0.18), width: 0.8) }
    }
    if snapshot.settings.axes {
      let extent = TorusMath.torusRadius + TorusMath.tubeRadius
      path([Vec3(-extent, 0, 0), Vec3(extent, 0, 0)], color: faded(green, 0.16), dash: 7)
      path([Vec3(0, -1.2, 0), Vec3(0, 1.2, 0)], color: faded(green, 0.16), dash: 7)
      path([Vec3(0, 0, -extent), Vec3(0, 0, extent)], color: faded(green, 0.16), dash: 7)
    }
  }

  private func timeTorus(retcon: Bool) {
    let now = snapshot.time
    let span = snapshot.horizon
    let s =
      retcon
      ? RetconMath.settings(base: snapshot.settings, phaseShift: snapshot.retconPhase)
      : snapshot.settings
    cage(retcon: retcon)
    if retcon {
      archiveTraces(snapshot.samples, ghostStrength: snapshot.ghostStrength, projection: torusPoint)
      // Sparse displacement links keep both histories readable. They use the
      // identical recorded timestamp, not the nearest current-frame time.
      let visible = snapshot.samples.filter { $0.t >= now - span && $0.t <= now }
      let stride = max(1, visible.count / 9)
      for index in Swift.stride(from: 0, to: visible.count, by: stride) {
        let sample = visible[index]
        for channel in 0..<3 {
          let rewritten = OrbitalMath.pointAt(sample.t, index: channel, settings: s)
          add(
            screen(torusPoint(sample.points[channel], offset: sample.t - now)),
            screen(torusPoint(rewritten, offset: sample.t - now)), color: faded(ghost, 0.24),
            width: 0.9, dash: 5)
        }
      }
      modelTraces(settings: s, from: now - span, to: now, dashed: false, projection: torusPoint)
    } else {
      archiveTraces(snapshot.samples, projection: torusPoint)
    }
    modelTraces(settings: s, from: now, to: now + span, dashed: true, projection: torusPoint)
    closure(settings: s, retcon: retcon)
    path(torusRing(offset: 0), color: faded(retcon ? ghost : amber, 0.85), width: 1.4, glow: s.glow)
    let current = OrbitalMath.pointsAt(now, settings: s).map { screen(torusPoint($0, offset: 0)) }
    if s.connections { connect(current) }
    for channel in 0..<3 { dot(current[channel], color: colors[channel]) }
    if retcon {
      retconInspection(settings: s)
    } else {
      inspection(projection: torusPoint, ring: torusRing)
    }
  }

  private func archiveTraces(
    _ samples: [TimelineSample], ghostStrength: Double? = nil,
    projection: (Vec4, Double) -> Vec3
  ) {
    let now = snapshot.time
    let earliest = now - snapshot.horizon
    for channel in 0..<3 {
      var last: TimelineSample?
      var distance: Float = 0
      for sample in samples {
        guard sample.t >= earliest, sample.t <= now else {
          last = nil
          continue
        }
        if let previous = last, sample.segment == previous.segment {
          let a = screen(projection(previous.points[channel], previous.t - now))
          let b = screen(projection(sample.points[channel], sample.t - now))
          add(
            a, b, color: ghostStrength.map { faded(ghost, $0) } ?? faded(colors[channel], 0.9),
            width: ghostStrength == nil ? 1.65 : 1.05,
            glow: ghostStrength == nil ? snapshot.settings.glow * 0.65 : 0,
            dash: ghostStrength == nil ? 0 : 7, offset: distance)
          distance = nextDashOffset(distance, from: a, to: b)
        } else {
          distance = 0
        }
        last = sample
      }
    }
  }

  private func modelTraces(
    settings: OrbitalSettings, from start: Double, to end: Double,
    dashed: Bool, projection: (Vec4, Double) -> Vec3
  ) {
    // Same 60 Hz evaluation grid as the recorder, directly emitted to the
    // reusable segment array: no thousands of temporary sample arrays/frame.
    let count = max(1, Int(ceil((end - start) * 60)))
    for channel in 0..<3 {
      var previous = screen(
        projection(
          OrbitalMath.pointAt(start, index: channel, settings: settings), start - snapshot.time))
      var distance: Float = 0
      for step in 1...count {
        let t = start + (end - start) * Double(step) / Double(count)
        let next = screen(
          projection(OrbitalMath.pointAt(t, index: channel, settings: settings), t - snapshot.time))
        add(
          previous, next, color: faded(colors[channel], dashed ? 0.75 : 0.95), width: 1.8,
          glow: settings.glow * (snapshot.kind == .retcon ? 0.85 : 0.65),
          dash: dashed ? 9 : 0, offset: distance)
        distance = nextDashOffset(distance, from: previous, to: next)
        previous = next
      }
    }
  }

  private func closure(settings s: OrbitalSettings, retcon: Bool) {
    let now = snapshot.time
    let span = snapshot.horizon
    let dt = span / Double(max(1, Int(ceil(span * 60))))
    let old = TimelineMath.recordedAt(snapshot.samples, time: now - span)
    let next = old.flatMap { first in snapshot.samples.first { $0.t > first.t } }
    guard retcon || (old != nil && next != nil) else { return }
    let bridgeTime = (2 * span * TorusMath.seamHalfAngle) / (.pi - TorusMath.seamHalfAngle)
    for channel in 0..<3 {
      let start =
        retcon ? OrbitalMath.pointAt(now - span, index: channel, settings: s) : old!.points[channel]
      let after =
        retcon
        ? OrbitalMath.pointAt(now - span + dt, index: channel, settings: s) : next!.points[channel]
      let vertices = TorusMath.closureBridge(
        end: OrbitalMath.pointAt(now + span, index: channel, settings: s),
        beforeEnd: OrbitalMath.pointAt(now + span - dt, index: channel, settings: s),
        start: start, afterStart: after, tangentScale: bridgeTime / (3 * dt)
      )
      path(vertices, color: faded(colors[channel], 0.85), width: 1.65, glow: s.glow * 0.65)
      // Snap only the display endpoint to the finite window boundary. The
      // recorded numerical timeline itself remains completely unchanged.
      if !retcon, let old, let next, old.segment == next.segment {
        path(
          [
            torusPoint(old.points[channel], offset: -span),
            torusPoint(next.points[channel], offset: next.t - now),
          ],
          color: faded(colors[channel], 0.9), width: 1.65, glow: s.glow * 0.65)
      }
    }
  }

  private func inspection(projection: (Vec4, Double) -> Vec3, ring: (Double) -> [Vec3]) {
    let offset = snapshot.inspectionOffset
    guard abs(offset) > 0.001 else { return }
    path(ring(offset), color: faded(ghost, 0.6), width: 1, dash: 6)
    let points =
      offset < 0
      ? TimelineMath.recordedAt(snapshot.samples, time: snapshot.time + offset)?.points
      : OrbitalMath.pointsAt(snapshot.time + offset, settings: snapshot.settings)
    if let points {
      for channel in 0..<3 {
        dot(
          screen(projection(points[channel], offset)), color: colors[channel], diameter: 10,
          hollow: true)
      }
    }
  }

  private func retconInspection(settings: OrbitalSettings) {
    let offset = snapshot.inspectionOffset
    let original =
      offset <= 0 ? TimelineMath.recordedAt(snapshot.samples, time: snapshot.time + offset) : nil
    let timestamp = original?.t ?? snapshot.time + offset
    let actualOffset = timestamp - snapshot.time
    path(torusRing(offset: actualOffset), color: faded(ghost, 0.55), width: 1, dash: 6)
    for channel in 0..<3 {
      let p = screen(
        torusPoint(
          OrbitalMath.pointAt(timestamp, index: channel, settings: settings), offset: actualOffset))
      if let original {
        let previous = screen(torusPoint(original.points[channel], offset: actualOffset))
        add(previous, p, color: faded(ghost, 0.75), width: 1, dash: 5)
        dot(previous, color: faded(ghost, 0.85), diameter: 11, hollow: true)
      }
      dot(p, color: colors[channel], diameter: 8)
    }
  }

  private func orbitalTracks() {
    let base = snapshot.settings
    let u = TrackMath.modulo(
      (snapshot.time - snapshot.loopEpoch) / max(0.01, snapshot.loopProgram.duration))
    let s =
      snapshot.loopEnabled
      ? TrackMath.loopSettings(base: base, u: u, program: snapshot.loopProgram) : base
    let shape = TrackMath.trackShapeKey(s)
    if shape != trackKey {
      tracks = (0..<3).map { channel in
        (0...320).map { step in
          TrackMath.trackPoint(phase: Double(step) / 320, index: channel, settings: s)
        }
      }
      trackKey = shape
    }
    cage()
    var nodes: [SIMD2<Float>?] = []
    nodes.reserveCapacity(3)
    for channel in 0..<3 {
      gradientPath(
        tracks[channel], channel: channel, alpha: 0.95, width: 1.8,
        glow: s.glow, projection: screen)
      let origin =
        snapshot.loopOrigins.indices.contains(channel) ? snapshot.loopOrigins[channel] : 0
      let phase =
        snapshot.loopEnabled
        ? TrackMath.loopPhase(u: u, index: channel, origin: origin, program: snapshot.loopProgram)
        : TrackMath.naturalPhase(snapshot.time, index: channel, settings: base)
      let wrapped = TrackMath.modulo(phase)
      if s.trails {
        let wake = (0...16).map { step in
          TrackMath.trackPoint(
            phase: wrapped - 0.03 + Double(step) / 16 * 0.03, index: channel, settings: s)
        }
        path(wake, color: colors[channel], width: 2.2, glow: s.glow)
      }
      nodes.append(screen(TrackMath.trackPoint(phase: wrapped, index: channel, settings: s)))
    }
    if s.connections { connect(nodes) }
    for channel in 0..<3 { dot(nodes[channel], color: colors[channel], diameter: 9) }
  }
}
