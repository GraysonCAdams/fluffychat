//
//  NotificationService.swift
//  Notification Extension
//
//  Created by Christian Pauly on 26.08.25.
//

import Intents
import UIKit
import Foundation
import UserNotifications
import os

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler:
            @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent =
            (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else { return }

        // Uncomment to read the push message payload:
        // os_log("[SeamPush] New message received: %{public}@", log: .default, type: .error, bestAttemptContent.userInfo)
        os_log("[SeamPush] New message received")


        var unread: Int?
        if let countsJson = bestAttemptContent.userInfo["counts"] as? String,
            let counts = try? JSONDecoder().decode(
                NotificationCounts.self,
                from: countsJson.data(using: .utf8)!
            )
        {
            unread = counts.unread
        } else if let count = bestAttemptContent.userInfo["unread_count"] as? NSNumber {
            unread = count.intValue
        }
        if let unread = unread {
            bestAttemptContent.badge = NSNumber(integerLiteral: unread)
        }

        // Check if notification contains room ID and event ID:
        guard let roomId = bestAttemptContent.userInfo["room_id"] as? String,
            let eventId = bestAttemptContent.userInfo["event_id"] as? String
        else {
            os_log("[SeamPush] Room ID or Event ID is missing!")
            let emptyContent = UNMutableNotificationContent()
            emptyContent.badge = bestAttemptContent.badge
            contentHandler(emptyContent)
            return
        }

        // Set thread identifier and fallback body:
        bestAttemptContent.body = String(
            localized: "New message - open app to read",
            comment: "Default notification body"
        )

        // Set badge and fallback title:
        bestAttemptContent.title = String(
            localized: "\(unread ?? 1) unread messages",
            comment: "Default notification title"
        )

        // Create database path:
        guard let containerPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.dev.threeonetwo.seam"
            ) else {
                os_log("[SeamPush] Unable to get container path!")
                contentHandler(bestAttemptContent)
                return
        }

        // The account the push is for names its database. A gateway that
        // relays the pusher's data sends it as `client_name`, or inside the
        // `devices` list as a JSON string; without either, the databases in
        // the app group are tried in turn, which is right for one account.
        var clientNames: [String] = []
        if let name = bestAttemptContent.userInfo["client_name"] as? String {
            clientNames = [name]
        } else if let devicesJson = bestAttemptContent.userInfo["devices"] as? String,
            let devices = try? JSONDecoder().decode(
                [NotificationDevice].self,
                from: devicesJson.data(using: .utf8)!
            ),
            let name = devices.first?.data.client_name
        {
            clientNames = [name]
        } else {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: containerPath.path)) ?? []
            // `<account>.search.sqlite` is the message search index.
            clientNames = files.filter { $0.hasSuffix(".sqlite") && !$0.hasSuffix(".search.sqlite") }
                .map { String($0.dropLast(".sqlite".count)) }
                .sorted()
        }

        // Open database:
        var opened: (name: String, database: SqlCipherDatabase)?
        var openError = "No account database in the app group"
        for name in clientNames {
            do {
                let path = containerPath.appendingPathComponent("\(name).sqlite").path
                opened = (name, try getDatabase(path: path))
                break
            } catch {
                openError = String(describing: error)
            }
        }
        guard let (clientName, database) = opened else {
            os_log("[SeamPush] Unable to open database: %{public}@", type: .error, openError)
            bestAttemptContent.userInfo["error"] = openError
            contentHandler(bestAttemptContent)
            return
        }

        bestAttemptContent.threadIdentifier = "\(clientName)_\(roomId)"

        // Get room name:
        var roomName = getRoomNameFromDatabase(
            database: database,
            roomId: roomId
        )
        var roomAvatarUrl = getRoomAvatarFromDatabase(database: database, roomId: roomId)
        // A chat with a name of its own, or with more than one other person,
        // is shown as a group: the banner then names the group and the
        // sender. Any other chat is shown as the sender alone.
        var isGroup = roomName != nil

        // Fall back to room heroes if no explicit room name
        if roomName == nil || roomAvatarUrl == nil {
            if let heroes = getRoomheroesFromDatabase(
                database: database,
                roomId: roomId
            ) {
                if heroes.count > 1 { isGroup = true }
                if !heroes.isEmpty {
                    roomName =
                        roomName
                        ?? heroes.map { hero in
                            hero.content.displayname
                                ?? String(localized: "Someone")
                        }.joined(separator: ", ")
                    roomAvatarUrl = roomAvatarUrl ?? heroes.first?.content.avatar_url
                } else {
                    roomName = roomName ?? String(localized: "Empty chat")
                }
            } else {
                roomName = roomName ?? String(localized: "New chat")
            }
        }

        if let roomName = roomName {
            bestAttemptContent.title = roomName
            bestAttemptContent.userInfo["room_name"] = roomName
        }
        
        var roomAvatarFile: URL?
        if let roomAvatarUrl = roomAvatarUrl {
            bestAttemptContent.userInfo["room_avatar"] = roomAvatarUrl
            do {
                roomAvatarFile = try downloadAttachment(url: roomAvatarUrl, containerPath: containerPath).url
            } catch {
                os_log("[SeamPush] Unable to download avatar!")
            }
        }
        let groupFlag = isGroup

        // The push carries only ids. Fetch the event and decrypt it here so
        // the banner shows who wrote and what; when that fails the banner
        // keeps the placeholder body set above.
        Task {
            do {
                let event = try await EventDecryptor(database: database)
                    .event(roomId: roomId, eventId: eventId)
                let senderProfile = getUserFromDatabase(
                    database: database, userId: event.senderId, roomId: roomId)?.content
                let sender = senderProfile?.displayname ?? event.senderId
                let text =
                    event.isReaction
                    ? event.relation?.key
                    : (event.isEdit ? event.newContentBody : nil) ?? event.body
                if let text {
                    // In a chat with one other person the title already is
                    // their name.
                    if sender != bestAttemptContent.title {
                        bestAttemptContent.subtitle = sender
                    }
                    bestAttemptContent.body = text

                    // As a communication notification the banner carries the
                    // sender's picture where the app icon would be, and in
                    // a group the group's picture and name with it.
                    var senderAvatarFile: URL?
                    if let avatarUrl = senderProfile?.avatar_url {
                        senderAvatarFile = try? self.downloadAttachment(
                            url: avatarUrl, containerPath: containerPath
                        ).url
                    }
                    if let communication = Self.communicationContent(
                        from: bestAttemptContent,
                        roomId: roomId,
                        roomName: bestAttemptContent.title,
                        isGroup: groupFlag,
                        groupAvatar: roomAvatarFile,
                        senderId: event.senderId,
                        senderName: sender,
                        senderAvatar: senderAvatarFile ?? (groupFlag ? nil : roomAvatarFile),
                        text: text)
                    {
                        contentHandler(communication)
                        return
                    }
                }
            } catch {
                os_log("[SeamPush] Unable to load event: %{public}@", type: .error, String(describing: error))
            }
            contentHandler(bestAttemptContent)
        }
    }

    /// `content` restyled as a message from `senderName`, or nil when the
    /// system refuses, which it does without the communication notifications
    /// entitlement.
    private static func communicationContent(
        from content: UNMutableNotificationContent,
        roomId: String,
        roomName: String,
        isGroup: Bool,
        groupAvatar: URL?,
        senderId: String,
        senderName: String,
        senderAvatar: URL?,
        text: String
    ) -> UNNotificationContent? {
        let senderImage =
            senderAvatar.flatMap { try? Data(contentsOf: $0) }.map { INImage(imageData: $0) }
            ?? initialsImage(for: senderName, seed: senderId)
        let person = INPerson(
            personHandle: INPersonHandle(value: senderId, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: senderImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: text,
            speakableGroupName: isGroup ? INSpeakableString(spokenPhrase: roomName) : nil,
            conversationIdentifier: roomId,
            serviceName: nil,
            sender: person,
            attachments: nil
        )
        if isGroup {
            let groupImage =
                groupAvatar.flatMap { try? Data(contentsOf: $0) }.map { INImage(imageData: $0) }
                ?? initialsImage(for: roomName, seed: roomId)
            intent.setImage(groupImage, forParameterNamed: \.speakableGroupName)
        }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        // The system writes the title and subtitle from the intent.
        content.subtitle = ""
        do {
            return try content.updating(from: intent)
        } catch {
            os_log("[SeamPush] Not a communication notification: %{public}@", type: .error, String(describing: error))
            return nil
        }
    }

    /// A round picture with the first letter of `name`, for someone or some
    /// chat without a picture, in a colour that stays the same for `seed`.
    private static func initialsImage(for name: String, seed: String) -> INImage {
        let size = CGSize(width: 192, height: 192)
        let hue = CGFloat(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        let letter = String(name.drop(while: { !$0.isLetter && !$0.isNumber }).prefix(1)).uppercased()
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.45, brightness: 0.75, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 88, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let bounds = (letter as NSString).size(withAttributes: attributes)
            (letter as NSString).draw(
                at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2),
                withAttributes: attributes)
        }
        return INImage(imageData: image.pngData() ?? Data())
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler,
            let bestAttemptContent = bestAttemptContent
        {
            contentHandler(bestAttemptContent)
        }
    }

    func getDatabase(path: String) throws -> SqlCipherDatabase {
        // Fetch database key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "flutter_secure_storage_service",
            kSecAttrAccount as String: "database_password",
            kSecReturnData as String: true,
            kSecAttrAccessGroup as String: "group.dev.threeonetwo.seam",
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            throw DatabaseKeyError.keychain(status)
        }
        
        return try SqlCipherDatabase.open(path: path, key: key)
    }

    func getUserFromDatabase(
        database: SqlCipherDatabase,
        userId: String,
        roomId: String
    ) -> UserEventJson? {
        let roomMemberDatabaseKey = [roomId, userId].joined(separator: "|")
        guard let event = try? database.scalar(
            query: "SELECT v FROM box_room_members WHERE k=?",
            args: [roomMemberDatabaseKey]
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(
            UserEventJson.self,
            from: Data(event.utf8),
        )
    }

    func getRoomAvatarFromDatabase(database: SqlCipherDatabase, roomId: String)
        -> String?
    {
        // Database key format: "roomId|eventType|stateKey"
        let roomAvatarDatabaseKey = [roomId, "m.room.avatar", ""].joined(
            separator: "|"
        )
        guard let event = try? database.scalar(
            query: "SELECT v FROM box_preload_room_states WHERE k=?",
            args: [roomAvatarDatabaseKey]
        ) else {
            return nil
        }
        
        let roomAvatarEvent = try? JSONDecoder().decode(
            RoomAvatarEventJson.self,
            from: event.data(using: .utf8)!
        )
        if let avatarUrl = roomAvatarEvent?.content.url, !avatarUrl.isEmpty {
            return avatarUrl
        }
        return nil
    }
    
    func getRoomNameFromDatabase(database: SqlCipherDatabase, roomId: String)
        -> String?
    {
        // Database key format: "roomId|eventType|stateKey"
        let roomNameDatabaseKey = [roomId, "m.room.name", ""].joined(
            separator: "|"
        )
        guard let event = try? database.scalar(
            query: "SELECT v FROM box_preload_room_states WHERE k=?",
            args: [roomNameDatabaseKey]
        ) else {
            return nil
        }
        
        let roomNameEvent = try? JSONDecoder().decode(
            RoomNameEventJson.self,
            from: event.data(using: .utf8)!
        )
        if let name = roomNameEvent?.content.name, !name.isEmpty {
            return name
        }
        return nil
    }

    func getRoomheroesFromDatabase(database: SqlCipherDatabase, roomId: String)
        -> [UserEventJson]?
    {
        guard let event = try? database.scalar(
            query: "SELECT v FROM box_rooms WHERE k=?",
            args: [roomId]
        ) else {
            return nil
        }
        
        let room = try? JSONDecoder().decode(
            RoomJson.self,
            from: event.data(using: .utf8)!
        )
        let heroes = room?.summary.heroes.map { hero in
            return getUserFromDatabase(
                database: database,
                userId: hero,
                roomId: roomId
            )
        }.compactMap { $0 }
        return heroes
    }
    
    func downloadAttachment(url: String, containerPath: URL) throws -> UNNotificationAttachment {
        let downloadDirectory = containerPath.appendingPathComponent("fluffychat_download_cache")
        
        let mxcComponents = url.replacingOccurrences(of: "mxc://", with: "").split(separator: "/")
        guard mxcComponents.count == 2 else {
            throw NSError(domain: "FamedlyPushHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid MXC URL format"])
        }
        
        let host = String(mxcComponents[0]).replacingOccurrences(of: ".", with: "_")
        let mediaId = String(mxcComponents[1])
        let fileName = "notification_\(host)_\(mediaId).jpg"
        let fileUrl = downloadDirectory.appendingPathComponent(fileName)
        
        return try UNNotificationAttachment(identifier: "image", url: fileUrl, options: nil)
    }
}

struct UserEventJson: Decodable {
    struct UserEventContentJson: Decodable {
        let displayname: String?
        let avatar_url: String?
    }
    let content: UserEventContentJson
}

struct RoomNameEventJson: Decodable {
    struct RoomNameEventContentJson: Decodable {
        let name: String?
    }
    let content: RoomNameEventContentJson
}

struct RoomAvatarEventJson: Decodable {
    struct RoomAvatarEventContentJson: Decodable {
        let url: String?
    }
    let content: RoomAvatarEventContentJson
}

struct RoomJson: Decodable {
    struct RoomSummaryJson: Decodable {
        let heroes: [String]
        enum CodingKeys: String, CodingKey {
            case heroes = "m.heroes"
        }
    }
    let summary: RoomSummaryJson
}

struct NotificationDevice: Decodable {
    struct NotificationDeviceData: Decodable {
        let client_name: String?
    }
    let data: NotificationDeviceData
}
struct NotificationCounts: Decodable {
    let unread: Int?
}

enum DatabaseKeyError: Error { case keychain(OSStatus), invalidData }
