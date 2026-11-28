import UIKit
import UniformTypeIdentifiers
import receive_sharing_intent

/// Takes whatever another app shares to Seam and hands it to the app.
///
/// Every attachment is one of three things: a web link, a piece of text, or
/// data. Data of any kind (a photo, a video, a document, a contact card, a
/// pass) is copied as a file into the app group's `SharedItems` folder, so
/// nothing is decoded here and the number of items is not limited by this
/// extension's memory. The list is then stored the way the
/// receive_sharing_intent plugin reads it in the app (`ShareKey` in the app
/// group's defaults, as its `SharedMediaFile`s) and the app is opened with
/// the plugin's `ShareMedia-<bundle id>:share` link.
///
/// If you get a "no such module 'receive_sharing_intent'" error, move
/// `Embed Foundation Extension` above `Thin Binary` in the Runner target's
/// build phases.
class ShareViewController: UIViewController {
  private var hostBundleId: String {
    let own = Bundle.main.bundleIdentifier ?? ""
    guard let dot = own.lastIndex(of: ".") else { return own }
    return String(own[..<dot])
  }

  private var appGroupId: String {
    (Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String)
      ?? "group.\(hostBundleId)"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()
    view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty, let folder = makeFolder() else {
      finish(with: [])
      return
    }

    // One slot per attachment, so the app gets them in the order they were
    // shared however the loads finish.
    var slots = [SharedMediaFile?](repeating: nil, count: providers.count)
    let lock = NSLock()
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
      group.enter()
      load(provider, index: index, into: folder) { file in
        lock.lock()
        slots[index] = file
        lock.unlock()
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      self?.finish(with: slots.compactMap { $0 })
    }
  }

  /// A folder of its own for this share, so two items with the same name do
  /// not overwrite one another across shares.
  private func makeFolder() -> URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else { return nil }
    let folder =
      container
      .appendingPathComponent("SharedItems", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      return folder
    } catch {
      return nil
    }
  }

  private func load(
    _ provider: NSItemProvider, index: Int, into folder: URL,
    done: @escaping (SharedMediaFile?) -> Void
  ) {
    let identifiers = provider.registeredTypeIdentifiers
    let types = identifiers.compactMap { UTType($0) }

    // A web link, unless the same item also comes as a file.
    let isFile = types.contains { $0.conforms(to: .fileURL) }
    if !isFile, types.contains(where: { $0.conforms(to: .url) }) {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        done(url.map { SharedMediaFile(path: $0.absoluteString, type: .url) })
      }
      return
    }

    // Text typed or selected in the other app, which has no file behind it.
    let textOnly = !types.isEmpty && types.allSatisfy { $0.conforms(to: .text) }
    if textOnly, !isFile, provider.canLoadObject(ofClass: String.self) {
      _ = provider.loadObject(ofClass: String.self) { text, _ in
        done(text.map { SharedMediaFile(path: $0, mimeType: "text/plain", type: .text) })
      }
      return
    }

    // Everything else is data: the most specific type the item offers that
    // is not just a pointer to a file.
    guard
      let identifier = identifiers.first(where: { id in
        guard let type = UTType(id) else { return false }
        return type.conforms(to: .data) && !type.conforms(to: .url)
      }) ?? identifiers.first
    else {
      done(nil)
      return
    }
    let type = UTType(identifier)
    provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, _ in
      // `source` is deleted when this block returns, so the copy is made here.
      guard let source = source else {
        done(nil)
        return
      }
      let name = Self.fileName(
        suggested: provider.suggestedName, source: source, type: type, index: index)
      let destination = folder.appendingPathComponent(name)
      do {
        try FileManager.default.copyItem(at: source, to: destination)
      } catch {
        done(nil)
        return
      }
      let kind: SharedMediaType
      if type?.conforms(to: .image) == true {
        kind = .image
      } else if type?.conforms(to: .movie) == true {
        kind = .video
      } else {
        kind = .file
      }
      done(
        SharedMediaFile(
          // The app expects the path undecoded, as the plugin's own
          // extension writes it.
          path: destination.absoluteString.removingPercentEncoding ?? destination.path,
          mimeType: type?.preferredMIMEType,
          type: kind))
    }
  }

  /// The name the other app suggests, with the type's extension if it has
  /// none; else the temporary file's own name. The index keeps two items of
  /// one share apart.
  static func fileName(suggested: String?, source: URL, type: UTType?, index: Int) -> String {
    var name = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    name = name.replacingOccurrences(of: "/", with: "-")
    if name.isEmpty { name = source.lastPathComponent }
    if (name as NSString).pathExtension.isEmpty {
      let ext = source.pathExtension.isEmpty ? type?.preferredFilenameExtension : source.pathExtension
      if let ext = ext, !ext.isEmpty { name += ".\(ext)" }
    }
    return index == 0 ? name : "\(index + 1)-\(name)"
  }

  private func finish(with files: [SharedMediaFile]) {
    guard !files.isEmpty, let data = try? JSONEncoder().encode(files) else {
      extensionContext?.cancelRequest(
        withError: NSError(domain: "dev.threeonetwo.seam.share", code: 1))
      return
    }
    let defaults = UserDefaults(suiteName: appGroupId)
    defaults?.set(data, forKey: kUserDefaultsKey)
    defaults?.removeObject(forKey: kUserDefaultsMessageKey)
    defaults?.synchronize()

    // An extension has no UIApplication of its own; the one hosting it is
    // found up the responder chain.
    if let url = URL(string: "\(kSchemePrefix)-\(hostBundleId):share") {
      var responder: UIResponder? = self
      while let current = responder {
        if let application = current as? UIApplication {
          application.open(url, options: [:], completionHandler: nil)
          break
        }
        responder = current.next
      }
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
