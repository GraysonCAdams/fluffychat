import CoreHaptics
import Flutter
import UIKit

/// Plays message effects' haptics on the Taptic Engine. It is the iOS side
/// of the `chat.fluffy.fluffychat/haptics` channel that
/// lib/utils/effect_haptics.dart drives, and speaks the same four calls as
/// Android's EffectHaptics.kt:
///
/// - `capabilities` answers the primitives this side plays, with how long
///   each lasts in milliseconds, and `amplitudeControl`.
/// - `compose` plays a list of `[primitive, scale, delayMs]`, each delay
///   counted from the end of the primitive before.
/// - `waveform` plays `timings` (milliseconds) with `amplitudes` (0 to 255)
///   one for one, or without them as off and on times in turn, off first.
/// - `predefined` plays `click`, `heavyClick` or `tick`.
///
/// Each call becomes one Core Haptics pattern, so its beats keep time with
/// the animation. The three that play answer whether a pattern was started.
final class EffectHaptics {
  static let shared = EffectHaptics()

  private var channel: FlutterMethodChannel?
  private var engine: CHHapticEngine?

  /// What a primitive is on the Taptic Engine: a tap, or a short vibration
  /// whose strength glides from `from` to `to`.
  private struct Primitive {
    let duration: TimeInterval
    let intensity: Float
    let sharpness: Float
    /// Start and end strength of a ramp, as shares of `intensity`. Nil for
    /// a tap.
    let ramp: (from: Float, to: Float)?
  }

  /// The primitives by the names the Dart side knows them by. Low sharpness
  /// reads as a dull thump and high sharpness as a crisp tick, which is how
  /// Android's thud, click and tick differ from one another.
  private static let primitives: [String: Primitive] = [
    "thud": Primitive(duration: 0.030, intensity: 1.0, sharpness: 0.1, ramp: nil),
    "click": Primitive(duration: 0.020, intensity: 0.8, sharpness: 0.6, ramp: nil),
    "tick": Primitive(duration: 0.010, intensity: 0.5, sharpness: 0.9, ramp: nil),
    "lowTick": Primitive(duration: 0.015, intensity: 0.4, sharpness: 0.2, ramp: nil),
    "quickRise": Primitive(duration: 0.150, intensity: 1.0, sharpness: 0.4, ramp: (0.1, 1.0)),
    "slowRise": Primitive(duration: 0.500, intensity: 1.0, sharpness: 0.3, ramp: (0.05, 1.0)),
    "quickFall": Primitive(duration: 0.100, intensity: 1.0, sharpness: 0.4, ramp: (1.0, 0.1)),
    "spin": Primitive(duration: 0.133, intensity: 0.6, sharpness: 0.7, ramp: (0.5, 1.0)),
  ]

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "chat.fluffy.fluffychat/haptics",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "capabilities":
        result(self.capabilities())
      case "compose":
        result(self.play(self.composition(call.arguments as? [Any] ?? [])))
      case "waveform":
        let arguments = call.arguments as? [String: Any]
        let timings = (arguments?["timings"] as? [NSNumber]) ?? []
        let amplitudes = arguments?["amplitudes"] as? [NSNumber]
        result(self.play(self.waveform(timings: timings, amplitudes: amplitudes)))
      case "predefined":
        result(self.play(self.predefined(call.arguments as? String)))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private var supportsHaptics: Bool {
    CHHapticEngine.capabilitiesForHardware().supportsHaptics
  }

  private func capabilities() -> [String: Any] {
    // An iPad has no Taptic Engine: no primitives and no strength control
    // leaves the Dart side nothing to plan.
    guard supportsHaptics else {
      return ["primitives": [String: Int](), "amplitudeControl": false]
    }
    var durations: [String: Int] = [:]
    for (name, primitive) in EffectHaptics.primitives {
      durations[name] = Int((primitive.duration * 1000).rounded())
    }
    return ["primitives": durations, "amplitudeControl": true]
  }

  // MARK: Patterns

  private func events(
    for primitive: Primitive,
    scale: Float,
    at time: TimeInterval
  ) -> [CHHapticEvent] {
    let sharpness = CHHapticEventParameter(
      parameterID: .hapticSharpness,
      value: primitive.sharpness
    )
    guard let ramp = primitive.ramp else {
      return [
        CHHapticEvent(
          eventType: .hapticTransient,
          parameters: [
            CHHapticEventParameter(
              parameterID: .hapticIntensity,
              value: primitive.intensity * scale
            ),
            sharpness,
          ],
          relativeTime: time
        )
      ]
    }
    // A ramp is a run of short vibrations, each a step stronger or weaker
    // than the last. Event parameters cannot change within one event, and a
    // parameter curve would scale every other event of the pattern too.
    let steps = max(2, Int((primitive.duration / 0.025).rounded()))
    let length = primitive.duration / Double(steps)
    return (0..<steps).map { index in
      let share = Float(index) / Float(steps - 1)
      let level = ramp.from + (ramp.to - ramp.from) * share
      return CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: primitive.intensity * level * scale
          ),
          sharpness,
        ],
        relativeTime: time + Double(index) * length,
        duration: length
      )
    }
  }

  private func composition(_ steps: [Any]) -> [CHHapticEvent] {
    var events: [CHHapticEvent] = []
    var cursor: TimeInterval = 0
    for step in steps {
      guard let fields = step as? [Any],
        let name = fields.first as? String,
        let primitive = EffectHaptics.primitives[name]
      else { return [] }
      let scale = min(1, max(0, (fields.count > 1 ? fields[1] as? NSNumber : nil)?.floatValue ?? 1))
      let delay = max(0, (fields.count > 2 ? fields[2] as? NSNumber : nil)?.doubleValue ?? 0) / 1000
      cursor += delay
      events += self.events(for: primitive, scale: scale, at: cursor)
      cursor += primitive.duration
    }
    return events
  }

  private func waveform(timings: [NSNumber], amplitudes: [NSNumber]?) -> [CHHapticEvent] {
    if let amplitudes = amplitudes, amplitudes.count != timings.count { return [] }
    var events: [CHHapticEvent] = []
    var cursor: TimeInterval = 0
    for (index, timing) in timings.enumerated() {
      let length = max(0, timing.doubleValue) / 1000
      // Without amplitudes the timings are off and on times in turn, off
      // first, at one strength.
      let level: Float
      if let amplitudes = amplitudes {
        level = min(1, max(0, amplitudes[index].floatValue / 255))
      } else {
        level = index % 2 == 1 ? 0.7 : 0
      }
      if level > 0 && length > 0 {
        events.append(
          CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
              CHHapticEventParameter(parameterID: .hapticIntensity, value: level),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
            ],
            relativeTime: cursor,
            duration: length
          )
        )
      }
      cursor += length
    }
    return events
  }

  private func predefined(_ name: String?) -> [CHHapticEvent] {
    let primitive: Primitive?
    switch name {
    case "heavyClick": primitive = EffectHaptics.primitives["thud"]
    case "tick": primitive = EffectHaptics.primitives["tick"]
    case "click": primitive = EffectHaptics.primitives["click"]
    default: primitive = nil
    }
    guard let primitive = primitive else { return [] }
    return events(for: primitive, scale: 1, at: 0)
  }

  // MARK: Engine

  private func startedEngine() throws -> CHHapticEngine {
    if let engine = engine {
      try engine.start()
      return engine
    }
    let engine = try CHHapticEngine()
    // The effects' sounds, where they have any, come from Flutter; an engine
    // that plays haptics only leaves the audio session alone.
    engine.playsHapticsOnly = true
    // The engine stops itself when idle and start() brings it back, so it
    // draws no power between effects.
    engine.isAutoShutdownEnabled = true
    engine.resetHandler = { [weak self] in
      // The system rebuilt the haptic server; the engine it left behind is
      // unusable.
      self?.engine = nil
    }
    try engine.start()
    self.engine = engine
    return engine
  }

  /// Starts `events` as one pattern; false when nothing was started.
  private func play(_ events: [CHHapticEvent]) -> Bool {
    guard supportsHaptics, !events.isEmpty else { return false }
    do {
      let engine = try startedEngine()
      let pattern = try CHHapticPattern(events: events, parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: CHHapticTimeImmediate)
      return true
    } catch {
      engine = nil
      return false
    }
  }
}
