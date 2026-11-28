import Flutter
import UIKit

/// Hands the device's APNs token to Dart over `dev.threeonetwo.seam/apns`.
///
/// Seam registers its Matrix pusher with the raw APNs token, so the token has
/// to cross from UIKit, which delivers it to the app delegate, to
/// lib/utils/apple_push.dart, which asks for it with `requestToken`.
final class ApnsTokenChannel {
  static let shared = ApnsTokenChannel()

  private var channel: FlutterMethodChannel?
  // Dart may ask again before UIKit has answered the first request; every
  // caller gets the same answer.
  private var pending: [FlutterResult] = []

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "dev.threeonetwo.seam/apns",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pending.append(result)
      UIApplication.shared.registerForRemoteNotifications()
    }
    self.channel = channel
  }

  func didRegister(deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    answer([
      "token": token,
      // A sandbox token is rejected by the production APNs host and the
      // other way round, so the gateway needs to know which one this is.
      "environment": ApnsTokenChannel.environment,
    ])
  }

  func didFail(error: Error) {
    answer(
      FlutterError(
        code: "apns_registration_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  private func answer(_ value: Any) {
    let waiting = pending
    pending = []
    for result in waiting {
      result(value)
    }
  }

  /// The APNs environment this install's token belongs to, which is set by
  /// how the app was signed and not by how it was compiled.
  ///
  /// A simulator only ever talks to the sandbox. On a device the
  /// provisioning profile says so in its `aps-environment` entitlement:
  /// `development` for a build run from Xcode, `production` for an ad hoc
  /// build. TestFlight and App Store builds carry no profile and are
  /// production.
  private static var environment: String {
    #if targetEnvironment(simulator)
      return "sandbox"
    #else
      guard
        let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
        let data = try? Data(contentsOf: url),
        // The profile is a signed envelope around a plist; the plist itself
        // is plain text inside it.
        let text = String(data: data, encoding: .isoLatin1),
        let start = text.range(of: "<plist"),
        let end = text.range(of: "</plist>"),
        let plist = try? PropertyListSerialization.propertyList(
          from: Data(text[start.lowerBound..<end.upperBound].utf8), options: [], format: nil)
          as? [String: Any],
        let entitlements = plist["Entitlements"] as? [String: Any],
        let aps = entitlements["aps-environment"] as? String
      else { return "production" }
      return aps == "development" ? "sandbox" : "production"
    #endif
  }
}
