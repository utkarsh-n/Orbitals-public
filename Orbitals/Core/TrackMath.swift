import Foundation

struct LoopProgram: Codable, Equatable, Hashable, Sendable {
  var duration: Double = 16
  var laps: Double = 2
  var depth: Double = 0.4
  var pace: Double = 1
  var excitation: Double = 2
  var radius: Double = 1
  var rotation: Double = 1

  static let presets: [String: LoopProgram] = [
    "Orbital cadence": LoopProgram(),
    "Resonance sweep": LoopProgram(
      duration: 24, laps: 3, depth: 0.75, pace: 2, excitation: 3, radius: 2, rotation: 2),
    "Slow drift": LoopProgram(
      duration: 32, laps: 1, depth: 0.25, pace: 1, excitation: 1, radius: 1, rotation: 1),
  ]
  static let presetNames = ["Orbital cadence", "Resonance sweep", "Slow drift"]
}

struct TrackShapeSignature: Equatable, Hashable, Sendable {
  struct ShapeChannel: Equatable, Hashable, Sendable {
    var motion: Motion
    var amplitude: Double
    var phase: Double
  }
  var radius: Double
  var morph: Double
  var fourD: Bool
  var xw: Double
  var yw: Double
  var zw: Double
  var channels: [ShapeChannel]

  init(_ settings: OrbitalSettings) {
    radius = settings.radius
    morph = settings.morph
    fourD = settings.fourD
    xw = settings.xw
    yw = settings.yw
    zw = settings.zw
    channels = settings.channels.map {
      ShapeChannel(motion: $0.motion, amplitude: $0.amplitude, phase: $0.phase)
    }
  }
}

enum TrackMath {
  static func modulo(_ value: Double, by modulus: Double = 1) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: modulus)
    return (remainder + modulus).truncatingRemainder(dividingBy: modulus)
  }

  static func periodTurns(motion: Motion, fourD: Bool) -> Double {
    motion == .precession ? 4 : (motion == .breathing && fourD ? 2 : 1)
  }

  static func naturalPhase(_ t: Double, index: Int, settings: OrbitalSettings) -> Double {
    let channel = settings.channels[index]
    return channel.frequency * channel.speed * t
      / periodTurns(motion: channel.motion, fourD: settings.fourD) + channel.phase / 360
  }

  static func trackPoint(phase: Double, index: Int, settings: OrbitalSettings) -> Vec3 {
    let v = cyclePoint(
      fraction: phase - settings.channels[index].phase / 360, index: index, settings: settings)
    let uv = TorusMath.projectCrossSection(v)
    return TorusMath.closedTubePoint(phase: phase, u: uv.x, v: uv.y)
  }

  /// The complete physical trajectory at unit rate. This is a shape guide, not a
  /// future timestamp: it stays useful when playback is paused or speed is zero.
  static func cyclePoint(fraction: Double, index: Int, settings: OrbitalSettings) -> Vec4 {
    let turns = periodTurns(motion: settings.channels[index].motion, fourD: settings.fourD)
    var canonical = settings.channels[index]
    canonical.frequency = 1 / OrbitalMath.tau
    canonical.speed = 1
    return OrbitalMath.pointAt(
      OrbitalMath.tau * turns * fraction, channel: canonical, settings: settings)
  }

  static func trackShapeKey(_ settings: OrbitalSettings) -> TrackShapeSignature {
    TrackShapeSignature(settings)
  }

  static func loopSettings(base: OrbitalSettings, u: Double, program: LoopProgram)
    -> OrbitalSettings
  {
    func wave(_ cycles: Double) -> Double {
      cycles == 0 ? 0 : sin(OrbitalMath.tau * cycles * u)
    }
    func pulse(_ value: Double, minimum: Double, maximum: Double, cycles: Double) -> Double {
      let w = wave(cycles)
      let positive = max(0, w)
      let negative = max(0, -w)
      return value + program.depth
        * (positive * positive * (maximum - value) - negative * negative * (value - minimum))
    }
    var result = base
    result.radius = pulse(base.radius, minimum: 0.5, maximum: 3, cycles: program.radius)
    result.xw = base.xw + 70 * program.depth * wave(program.rotation)
    result.yw = base.yw + 45 * program.depth * wave(program.rotation)
    for index in result.channels.indices {
      result.channels[index].amplitude = pulse(
        base.channels[index].amplitude, minimum: 0, maximum: 1, cycles: program.excitation)
    }
    return result
  }

  /// Integrated periodic speed is nonnegative for depth ∈ [0, 1] and closes at whole laps.
  static func loopPhase(u: Double, index: Int, origin: Double, program: LoopProgram) -> Double {
    let laps = program.laps + Double(index)
    let k = program.pace
    return origin + laps
      * (u
        + (k == 0 ? 0 : program.depth * (1 - cos(OrbitalMath.tau * k * u)) / (OrbitalMath.tau * k)))
  }
}
