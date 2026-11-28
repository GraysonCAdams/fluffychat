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
      // A debug build is signed for the APNs sandbox, where a production
      // token would be rejected, so the gateway needs to know which one this
      // is.
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

  private static var environment: String {
    #if DEBUG
      return "sandbox"
    #else
      return "production"
    #endif
  }
}
