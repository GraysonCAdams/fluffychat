import EventKit
import EventKitUI
import Flutter
import UIKit

/// iOS's data detectors for lib/utils/data_detectors, through
/// `NSDataDetector`. It is the iOS side of the
/// `chat.fluffy.fluffychat/data_detectors` channel that `ChannelDataDetector`
/// drives, and answers the same two calls as Android's DataDetectors.kt:
///
/// - `detect` with `text` and `referenceTime` (ms since the epoch) answers
///   the addresses, phone numbers, dates, dates with times and flights in
///   the text, in reading order, each with `start` and `end` as UTF-16
///   offsets and the actions iOS offers for it.
/// - `runAction` with `text` (the detected text alone) and `index` detects
///   `text` again and runs that detection's action number `index`. No token
///   is handed out, so nothing is held between the two calls.
///
/// `NSDataDetector` reads relative dates ("tomorrow") from the current time
/// and takes no reference date, so `referenceTime` is not applied: a relative
/// date in an old message resolves from today.
///
/// Flights carry no actions; the Dart side then offers Seam's own.
final class DataDetectors: NSObject, EKEventEditViewDelegate {
  static let shared = DataDetectors()

  private var channel: FlutterMethodChannel?
  private let queue = DispatchQueue(label: "dev.threeonetwo.seam.data-detectors", qos: .userInitiated)

  /// What a detection can do. The order within a type is the order of its
  /// actions on the wire: the first one is the chip under the bubble.
  enum Action {
    case openInMaps(String)
    case call(String)
    case faceTime(String)
    case createEvent(Date, allDay: Bool)
    case showInCalendar(Date)

    var title: String {
      switch self {
      case .openInMaps: return "Open in Maps"
      case .call: return "Call"
      case .faceTime: return "FaceTime"
      case .createEvent: return "Create Event"
      case .showInCalendar: return "Show in Calendar"
      }
    }
  }

  struct Detection {
    let type: String
    let range: NSRange
    let actions: [Action]
  }

  private static let detector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.address.rawValue
      | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
      | NSTextCheckingResult.CheckingType.date.rawValue
      | NSTextCheckingResult.CheckingType.transitInformation.rawValue
  )

  /// A clock time written out ("5pm", "17:30", "5 o'clock"). `NSDataDetector`
  /// gives a date without a time the time 12:00, so noon alone does not tell
  /// "on Friday" from "Friday at noon".
  private static let writtenTime = try? NSRegularExpression(
    pattern: "\\d\\s*(am|pm|a\\.m\\.|p\\.m\\.)|\\d{1,2}[:.]\\d{2}|o'?clock|noon|midnight",
    options: [.caseInsensitive]
  )

  /// The detections in `text` in reading order, none overlapping.
  static func detections(in text: String) -> [Detection] {
    guard let detector = detector else { return [] }
    let whole = NSRange(location: 0, length: (text as NSString).length)
    var found: [Detection] = []
    var covered = 0
    for match in detector.matches(in: text, options: [], range: whole) {
      guard match.range.location >= covered, match.range.length > 0 else { continue }
      let matched = (text as NSString).substring(with: match.range)
      let detection: Detection?
      switch match.resultType {
      case .address:
        detection = Detection(type: "address", range: match.range, actions: [.openInMaps(matched)])
      case .phoneNumber:
        let number = match.phoneNumber ?? matched
        detection = Detection(
          type: "phone", range: match.range, actions: [.call(number), .faceTime(number)])
      case .date:
        guard let date = match.date else { continue }
        let hasTime = Self.hasTime(date: date, matched: matched)
        detection = Detection(
          type: hasTime ? "datetime" : "date",
          range: match.range,
          actions: [.createEvent(date, allDay: !hasTime), .showInCalendar(date)])
      case .transitInformation:
        detection = Detection(type: "flight", range: match.range, actions: [])
      default:
        detection = nil
      }
      guard let detection = detection else { continue }
      found.append(detection)
      covered = match.range.location + match.range.length
    }
    return found
  }

  private static func hasTime(date: Date, matched: String) -> Bool {
    let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    if parts.hour != 12 || parts.minute != 0 || parts.second != 0 { return true }
    let range = NSRange(location: 0, length: (matched as NSString).length)
    return writtenTime?.firstMatch(in: matched, options: [], range: range) != nil
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "chat.fluffy.fluffychat/data_detectors", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard let text = arguments?["text"] as? String else {
      result(FlutterError(code: "bad_arguments", message: "text is missing", details: nil))
      return
    }
    switch call.method {
    case "detect":
      queue.async {
        let wire: [[String: Any]] = Self.detections(in: text).map { detection in
          [
            "type": detection.type,
            "start": detection.range.location,
            "end": detection.range.location + detection.range.length,
            "actions": detection.actions.map { ["title": $0.title] },
          ]
        }
        DispatchQueue.main.async { result(wire) }
      }
    case "runAction":
      guard let index = arguments?["index"] as? Int else {
        result(FlutterError(code: "bad_arguments", message: "index is missing", details: nil))
        return
      }
      queue.async {
        let actions = Self.detections(in: text).first?.actions ?? []
        DispatchQueue.main.async {
          guard actions.indices.contains(index) else {
            result(false)
            return
          }
          self.run(actions[index], result: result)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func run(_ action: Action, result: @escaping FlutterResult) {
    switch action {
    case .openInMaps(let address):
      var url = URLComponents(string: "maps://")
      url?.queryItems = [URLQueryItem(name: "q", value: address)]
      open(url?.url, result: result)
    case .call(let number):
      open(Self.dialURL(scheme: "tel", number: number), result: result)
    case .faceTime(let number):
      open(Self.dialURL(scheme: "facetime", number: number), result: result)
    case .showInCalendar(let date):
      // calshow: takes seconds since the reference date (2001-01-01).
      open(URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))"), result: result)
    case .createEvent(let date, let allDay):
      guard let presenter = Self.topViewController() else {
        result(false)
        return
      }
      let store = EKEventStore()
      let event = EKEvent(eventStore: store)
      event.startDate = date
      event.endDate = allDay ? date : date.addingTimeInterval(3600)
      event.isAllDay = allDay
      let editor = EKEventEditViewController()
      editor.eventStore = store
      editor.event = event
      editor.editViewDelegate = self
      presenter.present(editor, animated: true) { result(true) }
    }
  }

  /// `tel:` and `facetime:` take digits, with a leading `+` kept.
  static func dialURL(scheme: String, number: String) -> URL? {
    let digits = number.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "\(scheme):\(digits)")
  }

  private func open(_ url: URL?, result: @escaping FlutterResult) {
    guard let url = url else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var top = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  func eventEditViewController(
    _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
  }
}
