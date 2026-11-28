import Foundation
import os

#if canImport(SeamNseCrypto)
import SeamNseCrypto
#endif

/// Fetches the event a push points at and, when it is Megolm encrypted,
/// decrypts it with the keys the app keeps in its SQLCipher database.
///
/// Pushes carry only `room_id` and `event_id`. This reads the account's
/// homeserver, access token and user id from the `box_client` table, loads
/// the event from the homeserver, looks up its inbound group session in
/// `box_inbound_group_session` and decrypts it through `seam_nse_crypto`
/// (ios/seam_nse_crypto). The table layout is the matrix Dart SDK's
/// `MatrixSdkDatabase` on top of `SqfliteBox`: one `(k TEXT, v TEXT)` table
/// per box. ios/seam_nse_crypto/README.md lists the keys and where they come
/// from.
///
/// The database is only read. Megolm decryption does not advance any stored
/// state, and the replay record (`indexes`) is checked but not updated, so
/// the app stays the only writer. Message content, tokens and keys are never
/// logged.
struct EventDecryptor {
    let database: SqlCipherDatabase

    /// Time allowed for the event request. The extension gets roughly 30
    /// seconds in total and still has to deliver the notification.
    static let requestTimeout: TimeInterval = 8

    static let megolmAlgorithm = "m.megolm.v1.aes-sha2"

    private static let log = Logger(subsystem: "dev.threeonetwo.seam.nse", category: "EventDecryptor")

    func event(roomId: String, eventId: String) async throws -> NotificationEvent {
        let account = try readAccount()
        let raw = try await fetchEvent(account: account, roomId: roomId, eventId: eventId)

        guard let type = raw["type"] as? String, let sender = raw["sender"] as? String else {
            throw EventDecryptorError.malformedEvent
        }
        let content = raw["content"] as? [String: Any] ?? [:]

        guard type == "m.room.encrypted" else {
            return NotificationEvent(eventId: eventId, senderId: sender, type: type, content: content, wasEncrypted: false)
        }

        let decrypted = try decrypt(
            content: content,
            roomId: roomId,
            eventId: eventId,
            originServerTs: (raw["origin_server_ts"] as? NSNumber)?.int64Value,
            userId: account.userId
        )
        guard let innerType = decrypted["type"] as? String else {
            throw EventDecryptorError.malformedPlaintext
        }
        if let payloadRoom = decrypted["room_id"] as? String, payloadRoom != roomId {
            // A payload built for another room means the server replayed a
            // ciphertext here.
            throw EventDecryptorError.roomMismatch
        }
        var innerContent = decrypted["content"] as? [String: Any] ?? [:]
        // m.relates_to travels in the clear on encrypted events. The Dart SDK
        // takes it from the outer content (Encryption.decryptRoomEventSync),
        // so the notification classifies edits and reactions the same way.
        if let relatesTo = content["m.relates_to"] {
            innerContent["m.relates_to"] = relatesTo
        }
        return NotificationEvent(eventId: eventId, senderId: sender, type: innerType, content: innerContent, wasEncrypted: true)
    }

    // MARK: - Database

    struct Account {
        let homeserver: URL
        let accessToken: String
        let userId: String
    }

    /// Reads the client row values that `MatrixSdkDatabase.storeClient`
    /// writes into `box_client`. Values in a `Box<String>` are stored as the
    /// plain string, not JSON.
    func readAccount() throws -> Account {
        func value(_ key: String) throws -> String? {
            try database.scalar(query: "SELECT v FROM box_client WHERE k=?", args: [key])
        }
        guard let homeserverString = try value("homeserver_url"),
              let homeserver = URL(string: homeserverString),
              let token = try value("token"), !token.isEmpty,
              let userId = try value("user_id"), !userId.isEmpty
        else {
            throw EventDecryptorError.notLoggedIn
        }
        return Account(homeserver: homeserver, accessToken: token, userId: userId)
    }

    /// The `box_inbound_group_session` row for a session: a JSON object
    /// written by `StoredInboundGroupSession.toJson`, keyed by session id
    /// alone. `content`, `indexes`, `allowed_at_index` and
    /// `sender_claimed_keys` inside it are themselves JSON encoded strings.
    struct StoredSession {
        let roomId: String
        let sessionId: String
        let pickle: String
        /// Message index to `"<event id>|<origin_server_ts>"`, as keys
        /// `key-<index>`.
        let indexes: [String: String]
    }

    func readSession(sessionId: String) throws -> StoredSession? {
        guard let row = try database.scalar(
            query: "SELECT v FROM box_inbound_group_session WHERE k=?",
            args: [sessionId]
        ) else {
            return nil
        }
        guard let json = try JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any],
              let roomId = json["room_id"] as? String,
              let storedSessionId = json["session_id"] as? String,
              let pickle = json["pickle"] as? String
        else {
            throw EventDecryptorError.malformedSessionRow
        }
        var indexes: [String: String] = [:]
        if let indexesString = json["indexes"] as? String,
           let parsed = try? JSONSerialization.jsonObject(with: Data(indexesString.utf8)) as? [String: String] {
            indexes = parsed
        }
        return StoredSession(roomId: roomId, sessionId: storedSessionId, pickle: pickle, indexes: indexes)
    }

    // MARK: - Network

    func fetchEvent(account: Account, roomId: String, eventId: String) async throws -> [String: Any] {
        guard let url = Self.eventURL(homeserver: account.homeserver, roomId: roomId, eventId: eventId) else {
            throw EventDecryptorError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EventDecryptorError.malformedEvent }
        guard http.statusCode == 200 else {
            Self.log.error("Event request failed with HTTP \(http.statusCode, privacy: .public)")
            throw EventDecryptorError.http(status: http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EventDecryptorError.malformedEvent
        }
        return json
    }

    /// `GET /_matrix/client/v3/rooms/{roomId}/event/{eventId}` with both ids
    /// percent encoded as single path segments (`!`, `$` and `:` included).
    static func eventURL(homeserver: URL, roomId: String, eventId: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let room = roomId.addingPercentEncoding(withAllowedCharacters: unreserved),
              let event = eventId.addingPercentEncoding(withAllowedCharacters: unreserved)
        else {
            return nil
        }
        var base = homeserver.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/_matrix/client/v3/rooms/\(room)/event/\(event)")
    }

    // MARK: - Decryption

    func decrypt(
        content: [String: Any],
        roomId: String,
        eventId: String,
        originServerTs: Int64?,
        userId: String
    ) throws -> [String: Any] {
        guard let algorithm = content["algorithm"] as? String, algorithm == Self.megolmAlgorithm else {
            throw EventDecryptorError.unsupportedAlgorithm
        }
        guard let sessionId = content["session_id"] as? String,
              let ciphertext = content["ciphertext"] as? String
        else {
            throw EventDecryptorError.malformedEvent
        }
        // The Dart SDK drops a row whose session_id differs from the one it
        // asked for (KeyManager.loadInboundGroupSession). The room check is
        // stricter than the SDK, which keys rows by session id only: a key
        // shared for one room must not decrypt events in another.
        guard let stored = try readSession(sessionId: sessionId),
              stored.sessionId == sessionId,
              stored.roomId == roomId
        else {
            throw EventDecryptorError.unknownSession
        }

        let (plaintext, messageIndex) = try Self.megolmDecrypt(pickle: stored.pickle, userId: userId, ciphertext: ciphertext)

        // Replay check, as in Encryption.decryptRoomEventSync: a message index
        // already recorded for a different event means the ciphertext was
        // reused. An unrecorded index is accepted and left for the app to
        // record when it syncs.
        if let originServerTs,
           let seen = stored.indexes["key-\(messageIndex)"],
           seen != "\(eventId)|\(originServerTs)" {
            throw EventDecryptorError.replayedMessageIndex
        }

        guard let payload = try? JSONSerialization.jsonObject(with: Data(plaintext.utf8)) as? [String: Any] else {
            throw EventDecryptorError.malformedPlaintext
        }
        return payload
    }

    /// Calls into seam_nse_crypto. The pickle keys are derived from the user
    /// id inside the library, the same way the Dart SDK derives them.
    static func megolmDecrypt(pickle: String, userId: String, ciphertext: String) throws -> (String, UInt32) {
        var out: UnsafeMutablePointer<CChar>?
        var messageIndex: UInt32 = 0
        let code = seam_megolm_decrypt_for_user(pickle, userId, ciphertext, &out, &messageIndex)
        guard code == 0, let out else {
            log.error("Megolm decryption failed with code \(code, privacy: .public)")
            throw EventDecryptorError.decryption(code: code)
        }
        defer { seam_string_free(out) }
        return (String(cString: out), messageIndex)
    }
}

enum EventDecryptorError: Error {
    case notLoggedIn
    case invalidURL
    case http(status: Int)
    case malformedEvent
    case malformedSessionRow
    case malformedPlaintext
    case unsupportedAlgorithm
    case unknownSession
    case roomMismatch
    case replayedMessageIndex
    /// A `SEAM_ERR_*` code from seam_nse_crypto.h.
    case decryption(code: Int32)
}

/// The parts of a (decrypted) event a notification needs.
struct NotificationEvent {
    struct Relation {
        /// `rel_type`: `m.replace` for edits, `m.annotation` for reactions,
        /// `m.thread` for thread messages.
        let relType: String?
        let eventId: String?
        /// The reaction key of an `m.annotation`.
        let key: String?
        /// `m.in_reply_to.event_id`.
        let inReplyTo: String?
        /// `is_falling_back` on thread relations: the reply is only a
        /// fallback for clients without threads.
        let isFallingBack: Bool
    }

    /// An `m.room.message` media `file`: an encrypted attachment and the
    /// JWK key, IV and hash needed to decrypt it.
    struct EncryptedFile {
        let url: String
        let key: String
        let iv: String
        let sha256: String
        /// The raw JSON object, for code that needs more than the fields above.
        let json: [String: Any]
    }

    let eventId: String
    let senderId: String
    let type: String
    let wasEncrypted: Bool
    let msgtype: String?
    let body: String?
    /// `format` of `formatted_body`, normally `org.matrix.custom.html`.
    let format: String?
    let hasFormattedBody: Bool
    /// `m.new_content` of an edit, which holds the replacement body.
    let newContentBody: String?
    let newContentMsgtype: String?
    /// Plain media `url` (an mxc URI) of an unencrypted attachment.
    let mediaUrl: String?
    let mediaFile: EncryptedFile?
    let mimetype: String?
    let relation: Relation?

    var isEdit: Bool { relation?.relType == "m.replace" }
    var isReaction: Bool { type == "m.reaction" || relation?.relType == "m.annotation" }

    init(eventId: String, senderId: String, type: String, content: [String: Any], wasEncrypted: Bool) {
        self.eventId = eventId
        self.senderId = senderId
        self.type = type
        self.wasEncrypted = wasEncrypted
        msgtype = content["msgtype"] as? String
        body = content["body"] as? String
        format = content["format"] as? String
        hasFormattedBody = content["formatted_body"] is String

        let newContent = content["m.new_content"] as? [String: Any]
        newContentBody = newContent?["body"] as? String
        newContentMsgtype = newContent?["msgtype"] as? String

        mediaUrl = content["url"] as? String
        if let file = content["file"] as? [String: Any],
           let url = file["url"] as? String,
           let key = (file["key"] as? [String: Any])?["k"] as? String,
           let iv = file["iv"] as? String,
           let sha256 = (file["hashes"] as? [String: Any])?["sha256"] as? String {
            mediaFile = EncryptedFile(url: url, key: key, iv: iv, sha256: sha256, json: file)
        } else {
            mediaFile = nil
        }
        mimetype = (content["info"] as? [String: Any])?["mimetype"] as? String

        if let relatesTo = content["m.relates_to"] as? [String: Any] {
            relation = Relation(
                relType: relatesTo["rel_type"] as? String,
                eventId: relatesTo["event_id"] as? String,
                key: relatesTo["key"] as? String,
                inReplyTo: (relatesTo["m.in_reply_to"] as? [String: Any])?["event_id"] as? String,
                isFallingBack: relatesTo["is_falling_back"] as? Bool ?? false
            )
        } else {
            relation = nil
        }
    }
}
