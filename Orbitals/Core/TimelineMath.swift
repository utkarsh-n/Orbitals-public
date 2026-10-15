import Foundation

struct TimelineSample: Codable, Equatable, Sendable {
  var t: Double
  var points: [Vec4]
  var segment: Int
}

struct TimelineRecorder: Sendable {
  private(set) var samples: [TimelineSample] = []
  private(set) var segment = 0
  private(set) var lastTime = -Double.infinity
  private var signature: MotionSignature?
  private var nextSample = 0.0

  init() { samples.reserveCapacity(1_804) }

  mutating func clear() { self = TimelineRecorder() }

  /// Archive exact 60 Hz simulation-time ticks. Edits while paused can alter only
  /// the next model segment, never the coordinates of an existing snapshot.
  mutating func record(at t: Double, settings: OrbitalSettings) {
    guard t.isFinite else { return }
    if t < lastTime - 1e-9 { clear() }
    let newSignature = MotionSignature(settings)
    let changed = newSignature != signature
    if changed {
      segment += 1
      signature = newSignature
      nextSample = t
    }
    let advanced = t > lastTime + 1e-9
    if samples.isEmpty || (advanced && (changed || samples.last?.segment != segment)) {
      samples.append(
        TimelineSample(t: t, points: OrbitalMath.pointsAt(t, settings: settings), segment: segment))
      nextSample = t + TimelineMath.sampleInterval
    } else if advanced {
      // Do not compute ticks already outside the retained archive after a long suspension.
      let earliest = t - TimelineMath.historySeconds
      if nextSample < earliest - 1e-9 {
        nextSample +=
          floor((earliest - nextSample) / TimelineMath.sampleInterval) * TimelineMath.sampleInterval
      }
      while nextSample <= t + 1e-9 {
        samples.append(
          TimelineSample(
            t: nextSample, points: OrbitalMath.pointsAt(nextSample, settings: settings),
            segment: segment))
        nextSample += TimelineMath.sampleInterval
      }
    } else if changed {
      nextSample = t + TimelineMath.sampleInterval
    }
    lastTime = t
    let trim = samples.partitioningIndex { $0.t >= t - TimelineMath.historySeconds - 1e-9 }
    if trim > 0 { samples.removeFirst(trim) }
  }
}

enum TimelineMath {
  static let historySeconds = 30.0
  static let sampleInterval = 1.0 / 60.0

  static func forecast(now: Double, horizon: Double, settings: OrbitalSettings) -> [TimelineSample]
  {
    guard now.isFinite, horizon.isFinite, horizon >= 0 else { return [] }
    let count = Int(ceil(horizon / sampleInterval))
    return (0...count).map { index in
      let t = now + min(Double(index) * sampleInterval, horizon)
      return TimelineSample(t: t, points: OrbitalMath.pointsAt(t, settings: settings), segment: 0)
    }
  }

  static func recordedAt(_ samples: [TimelineSample], time: Double) -> TimelineSample? {
    guard let first = samples.first, let last = samples.last,
      time >= first.t - 1e-9, time <= last.t + sampleInterval
    else { return nil }
    var low = 0
    var high = samples.count - 1
    while low < high {
      let middle = (low + high + 1) / 2
      if samples[middle].t <= time + 1e-9 { low = middle } else { high = middle - 1 }
    }
    return samples[low]
  }

  static func splitSegments(_ samples: [TimelineSample]) -> [[TimelineSample]] {
    var result: [[TimelineSample]] = []
    for sample in samples {
      if result.last?.last?.segment != sample.segment {
        result.append([sample])
      } else {
        result[result.count - 1].append(sample)
      }
    }
    return result
  }
}

extension Array {
  /// First index satisfying a monotonic predicate, including endIndex.
  fileprivate func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
    var low = 0
    var high = count
    while low < high {
      let middle = (low + high) / 2
      if predicate(self[middle]) { high = middle } else { low = middle + 1 }
    }
    return low
  }
}
