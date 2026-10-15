import Foundation

struct RetconBranch: Sendable {
  private(set) var revision = 0
  private(set) var samples: [TimelineSample] = []
  private var signature: MotionSignature?
  private var archiveStart = -1.0
  private var archiveEnd = -1.0
  private var archiveCount = 0
  private var generation: Int?

  /// archiveGeneration changes on a recorder replacement, since Swift arrays use value semantics.
  mutating func update(
    archive: [TimelineSample], settings: OrbitalSettings, archiveGeneration: Int = 0
  ) {
    let newSignature = MotionSignature(settings)
    let start = archive.first?.t ?? -1
    let end = archive.last?.t ?? -1
    let reset =
      end < archiveEnd || archive.isEmpty || (generation != nil && generation != archiveGeneration)
    if reset {
      samples.removeAll(keepingCapacity: true)
      revision = 0
      signature = nil
    }
    let changed = signature != newSignature
    if changed { revision += 1 }
    if changed || reset || start != archiveStart || end != archiveEnd
      || archive.count != archiveCount
    {
      // This branch is rewritten retroactively. The archived evidence remains untouched.
      samples = archive.map {
        TimelineSample(t: $0.t, points: OrbitalMath.pointsAt($0.t, settings: settings), segment: 0)
      }
    }
    signature = newSignature
    archiveStart = start
    archiveEnd = end
    archiveCount = archive.count
    generation = archiveGeneration
  }
}

enum RetconMath {
  static func settings(base: OrbitalSettings, phaseShift: Double) -> OrbitalSettings {
    var result = base
    for index in result.channels.indices {
      result.channels[index].phase = TrackMath.modulo(
        base.channels[index].phase + phaseShift, by: 360)
    }
    return result
  }

  static func rewriteDistances(original: TimelineSample?, rewritten: TimelineSample?) -> [Double]? {
    guard let original, let rewritten, original.points.count == rewritten.points.count else {
      return nil
    }
    return zip(original.points, rewritten.points).map { OrbitalMath.distance($0, $1) }
  }
}
