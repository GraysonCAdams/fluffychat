# Merged contacts

One person reached over several networks (iMessage, SMS/RCS, Telegram) shows
as one chat, with one timeline and a chosen network to send from. Matrix has
no such concept, so this is a client feature whose state syncs between this
fork's installs through account data. Other clients keep seeing the separate
rooms, and nothing is written into the rooms themselves.

## Scope

- Direct chats only. A merged contact is a set of 1:1 rooms with the same
  person. Group chats are never merged.
- Rooms stay separate on the server. Unmerging loses nothing.
- Every message is sent into exactly one room. Nothing is cross-posted.

## Data model

One account data event, `im.fluffychat.merged_contacts`:

```json
{
  "version": 1,
  "contacts": {
    "c_7f3a": {
      "name": "Harrison Young",
      "rooms": ["!imsg:example.org", "!gmsg:example.org"],
      "send_via": "!imsg:example.org",
      "send_mode": "preferred",
      "updated": 1795449600000
    }
  },
  "dismissed_suggestions": [["!a:example.org", "!b:example.org"]]
}
```

- `rooms`: ordered, most preferred first. A room belongs to at most one
  contact. The first entry is the fallback order after `send_via`.
- `send_mode`: `preferred` (always `send_via` unless the user picks another
  for one message) or `last_received` (reply on the network they last wrote
  from).
- `name` is optional. Without it the display name of the `send_via` room is
  used.
- `fallback` (optional, default false) turns on the offer to resend a failed
  message through the next network (see SendRouter).
- Conflicts between devices: last write wins per contact, by `updated`. The
  whole event is small, so it is rewritten on every change. Since account
  data is replaced whole, a device that sees its own edit (made within the
  last five minutes) overwritten by another device's copy reconciles the two
  per contact and writes the result back.
- Unmerging leaves a tombstone, `{"removed": true, "rooms": [], "updated":
  ...}`, so an older copy of the contact on another device cannot bring it
  back. Tombstones older than 30 days are dropped on the next write.
- Rooms that are left are dropped from a contact
  when the event is read. A contact with fewer than two rooms dissolves. This
  happens in the in-memory view only: the stored contact keeps the room, so a
  room that is briefly missing (rooms not loaded yet, a stale `m.direct`)
  comes back on its own. When two contacts claim one room, the more recently
  updated one keeps it.

## Layers

```
MergedContactsStore        account data <-> in-memory index (roomId -> contact)
MergedContact              rooms, send_via, derived name/avatar/unread/last event
MergedTimeline             k-way merge of the rooms' Timelines
SendRouter                 which room a new message, reply, reaction goes to
MergeSuggester             finds rooms that look like the same person
UI                         chat list tile, merged chat screen, app bar network buttons, manage sheet
```

### MergedContactsStore (`lib/utils/merged_contacts/store.dart`)

- Loads from `client.accountData`, listens to `onSync` for changes to the
  event type, exposes `contactForRoom(roomId)` in O(1) and a change
  notifier (`revision`).
- All writes go through it: `merge(rooms)`, `unmerge(contactId)`,
  `removeRoom`, `setSendVia`, `setSendMode`, `rename`, `reorderRoom`,
  `dismissSuggestion`. A write shows at once and is undone if the server
  rejects it.
- One store per client, reached through `MergedContactsStore.forClient`
  rather than the `Matrix` widget, so the push handler, which runs without
  the widget tree, sees the same contacts. Account data and room access go
  through a small backend interface so the store is unit tested without a
  server.

### MergedContact

Derived, never stored:

- last event: newest `lastEvent` across rooms
- unread and highlight counts: sums; `isUnread` if any room is
- avatar and name: from the `send_via` room unless `name` is set
- networks: the bridge each room belongs to, for badges (from the room's
  parent space, the same source as the chat list's corner badge)
- muted: only if every room is muted

### MergedTimeline (`lib/utils/merged_contacts/merged_timeline.dart`)

Wraps one SDK `Timeline` per room.

- `events`: merge of the rooms' event lists by `originServerTs`, newest
  first, ties broken by room order then event ID so the order is stable.
- Recomputed incrementally: each child timeline's `onInsert/onChange/
  onRemove` maps to an index in the merged list.
- `requestHistory()`: asks the room whose oldest loaded event is newest, so
  the merged list never has a gap: an event is only shown once every room
  has loaded back to its timestamp, or has no more history. That boundary
  ("safe horizon") is the max over rooms of their oldest loaded timestamp.
  Events older than the horizon stay hidden until the other rooms catch up.
  The bound is strict: events at exactly the horizon wait too, since a room
  can hold more events with that same timestamp. A room that keeps
  answering history requests with nothing new (three times in a row) while
  claiming to have more stops holding the horizon, so it cannot hide the
  others' history for good.
- `canRequestHistory`: true while any room can.
- Jump to an event: load context in its own room, and open each other room
  around its event nearest that time (`timestamp_to_event`), as fragments
  too. Fragments add an upper bound to the window, the min over rooms of
  their newest loaded timestamp, and loading newer events asks the room
  holding it. A room with nothing that old opens live.
- Read marker: per room. The merged "new messages" line sits above the
  oldest unread event across rooms.

The ordering, the window and the choice of room to load from live in
`MergedOrder` (`merged_order.dart`), generic over the event type and unit
tested with plain values, including a run that loads history step by step
and checks shown events never change. Changes in a room map to inserts,
removals and updates at merged indexes by diffing the merged list.

`ChatController` today owns a single `Room` and `Timeline`. Rather than a
new `ChatTimelineSource` interface, `MergedTimeline` implements the SDK's
`Timeline` (forwarding to the rooms' timelines), so the event list, message
widgets, reply and edit lookups and scroll code take it unchanged: the
change to the controller is choosing which timeline to open. Message
widgets already take an `Event` that carries its own `room`, so per-event
actions keep working. In a merged chat the controller's `room` is the
composer's target room, so everything that reads it (encryption,
permissions, typing) follows the target network.

### SendRouter (`lib/utils/merged_contacts/send_router.dart`)

| Action | Goes to |
|---|---|
| New message, attachment, voice message, sticker, location, poll | the composer's current target room |
| Reply, thread reply, reaction, edit, redaction, pin | the room of the event acted on |
| Read receipt | each room, up to its own newest visible event |
| Typing notification | the composer's target room |
| Draft | stored per contact (`draft_contact_<id>`), not per room |

The preferred network only decides where a message that starts something
new goes. Anything that acts on an existing message (reply, reaction, edit,
redaction, thread reply) must go out on the network that message is on, from
the account the user has on that network, whatever `send_via` says: an
iMessage reaction cannot be delivered through SMS. While the user is
replying, editing or writing in a thread, the network buttons in the app bar
show that message's network and do not respond, so it is clear the answer
will not use the default.

Every send in the chat screen asks `SendRouter` (`route(action,
eventRoomId:)` and `composerTarget(editRoomId:, replyRoomId:,
threadRoomId:)`); an action on a message without that message's room is an
error, not a default. Message widgets, which have no router, reach the room
through `event.roomFor(action)` (`routed_event.dart`), which states the same
rule. The router works on room IDs only and is unit tested per action.

Target room for a new message:

1. The network picked in the app bar (`ChatNetworkIcons`). Picking also
   stores it as the contact's `send_via`, so the next visit starts on it.
2. `send_mode == last_received`: room of the newest incoming event.
3. `send_via`.

Fallback is opt-in per contact and only on a definite failure: if the send
ends in `EventStatus.error`, offer "Send via <next network> instead" on the
failed bubble. It does not resend by itself, since a silent SMS fallback can
leak a message meant for an encrypted network. The switch is in the manage
sheet (`fallback` in the data model). The offer appears in the failed
message's selection bar and context menu, for text, emote and notice
messages that start something new: a reply, thread reply or edit belongs to
its message's network and is never moved, and a failed attachment may not
have uploaded, so it is retried where it was. "Next" is the following room
in the contact's order, wrapping around (`SendRouter.fallbackRoomFor`). The
failed copy is removed once the new one is on its way.

Attachments are fitted to the room they actually go to, not the room on
screen. Each mautrix bridge publishes what its network accepts in a
`com.beeper.room_features` state event (state key is the bridge's own);
`RoomFeatures` (`lib/utils/room_features.dart`) reads the newest one, and
`adaptMediaForRoom` (`lib/utils/media_adaptation.dart`) applies it before
`sendFileEvent` in `sendAttachments`, `SendFileDialog`, voice messages and
keyboard-inserted media. An image type the room does not take is re-encoded
as PNG, a video as MP4 where the platform can transcode (Android, iOS,
macOS), else either goes as `m.file` if the room takes that type as a file;
otherwise, or over the room's `max_size`, nothing is sent and a snackbar names
what the chat accepts. A caption the room refuses is sent as its own text
message after the media. A room without the event behaves as before.

### MergeSuggester (`lib/utils/merged_contacts/suggester.dart`)

Groups direct chats that share an identifier and never merges without the
user. Each chat is matched on two things: its display name, and a primary
identifier, the first one available in this order:

1. **Phone number**, normalised to E.164. Sources: the iMessage bridge's
   user IDs (`@imessage_tel=3a+1404...`), and the `com.beeper.bridge.
   identifiers` list in a contact's profile. The Google Messages bridge only
   publishes that list with `phone_numbers_in_profile: true` in its config,
   which this feature assumes is set.
2. **Email address**, lower-cased, from the same sources (`@imessage_
   mailto=3a...`).
3. **Display name**, normalised (case, whitespace, punctuation).

Two rules apply before any match. A chat titled with a bare phone number,
short code or email address is unnamed and is never suggested: those are
mostly automated senders, and a number alone does not say who would be
merged. A group with two chats on the same network is skipped whatever it
matched on, because that is a duplicate room from the bridge rather than one
person on two networks.

Two chats land in one group when they share the primary identifier or the
name. The name is needed because bridges expose different things: one puts
the number in the user ID, another shows only the contact's name. A group
that shares a phone number or email is a strong suggestion; one that shares
only a name is weak, since two people can share a name. Both are offered in
the banner, strong ones first. The identifier a suggestion matched on is
shown with it ("Same number: +1 404 ..."). Dismissals are stored in
`dismissed_suggestions`.

#### Phone number normalisation

Bridges format numbers differently (`+14045551234`, `tel:+1404...`,
`(404) 555-1234`, `404-555-1234`, `1 404 555 1234`, URL-encoded as
`3a+1404...` in user IDs), so every number passes through one function,
`normalizePhone(raw, defaultRegion)`, before it is compared or stored:

1. Decode the bridge's escaping (`=3a` is `:`), drop a `tel:` prefix and
   any extension (`;ext=`, `x123`).
2. Strip everything except digits and a leading `+`; turn a leading `00`
   into `+`.
3. No `+`: apply the default region. For `US`, 10 digits get `+1`, and 11
   digits starting with `1` get `+`.
4. Result must be `+` and 8 to 15 digits (E.164). Anything else, such as
   short codes (`83356`) and alphanumeric senders, is not a phone identifier
   and falls through to name matching.

The default region comes from the merged contacts settings ("United States
and Canada" or "Elsewhere"), else the device locale's country, else the US.
No bridge used here exposes the user's own number, so that source is not
read.
Comparison is exact on the normalised form. A full library (libphonenumber)
is not needed for this and would add size; the function is small and unit
tested with each bridge's real formats.

The matched identifier is also saved on the contact as `identifier`
(`{"type": "phone", "value": "+1404..."}`), so a new chat with the same
number on another network can be offered for the existing contact.

`MergeSuggestionService` (`suggestion_service.dart`, one per client) runs
the suggester off the chat list's build path: after the first sync, then
three seconds after the direct chats (joins, leaves, `m.direct`, member or
name changes) or the merged contacts change. Profile identifiers are only
fetched for bridge ghosts (a `<bridge>_` localpart) whose user ID carries
no number or email, one request at a time and at most 50 per pass, through
`GET /profile/{user}/com.beeper.bridge.identifiers`. Answers are cached on
the device for seven days, an empty answer for one day (the bridge may
start publishing numbers), and a failed request is retried on the next
pass.

## UI

### Chat list

- One tile per contact, sorted by the contact's newest event. Member rooms
  are hidden from the list (and from space views) while merged. The contact
  takes the place of the first of its rooms in the SDK's room order, which is
  pinned first, then newest first (`MergedChatList` in
  `lib/pages/chat_list/merged_contact_list.dart`).
- A contact passes a filter (Unread, a source space, the space being
  viewed) when any of its rooms does, and counts as unread for the
  unread-below chip and the pinned row when any room is unread. It sits in
  the pinned row when any of its rooms is pinned.
- Avatar full size, with up to two network badges in the corner and "+N"
  beyond that.
- Search matches the contact name and each member room's name.
- Long press: Unmerge, Manage, plus the usual actions applied to every room
  (mute, pin, mark read).
- Entry points to merge: long press a direct chat -> "Merge with...", which
  opens a picker of direct chats where several can be ticked at once, and
  the suggestion banner. This branch's chat list has no multi-select mode,
  so the picker takes the place of multi-selecting chats in the list.
- The chat's app bar ends its network switcher with a dashed "+" that
  lists the chats which qualify (`mergeCandidates` in
  `lib/pages/chat/add_merged_chat.dart`): a one-to-one chat takes
  one-to-one chats with the same phone number, a group chat takes group
  chats with the same name, and either way only on a network the
  conversation does not span yet. With none, the "+" opens a dialog saying
  so. This is the one way a group chat joins a
  contact; suggestions and the picker list direct chats only.

### New chat

New chat (`lib/pages/new_private_chat/`) merges three sources into one
row per person (`mergeNewChatPeople` in
`lib/utils/new_chat/new_chat_people.dart`), followed by the server's user
directory:

1. The user's chats the search finds, a merged contact as one row.
2. The contacts each bridge lists through its provisioning API
   (`lib/utils/bridge_provisioning.dart`). The homeserver's front end
   proxies `{homeserver}/_matrix/client/unstable/net.graysons.bridge/{name}/v3/...`
   to the bridge's `/_matrix/provision/v3/...`; the bridges tried are the
   `provisionedBridgeNames` list, and one whose `whoami` fails is skipped.
   A bridge that answers `contacts` with `M_UNRECOGNIZED` (iMessage) has
   no list. Requests carry the user's access token and `user_id`.
3. On Android, the phone's address book (`flutter_contacts`), once the
   user allows it from a row in the list. Saying no is remembered
   (`phoneContactsDeclined`) and the row is not shown again.

A bridge contact or address book entry joins a row with the same phone
number (`normalizePhone`), then email, then bridge ghost; two chats are
never merged here. Each row ends with grey icons of the networks that reach
the person. A typed phone number nobody has gets a row of its own.

Tapping a row with a chat opens it. Any other row opens a sheet of the
user's networks, iMessage first, then Google Messages, then the rest; each
is asked `resolve_identifier` for the person (the ghost's ID when that
bridge listed them, else the number, else the email) and only those that
can reach them are tappable. Numbers from the address book are sent only to
these bridges, and only for the person tapped. Picking a network reuses the
direct chat the bridge reports, else calls `create_dm`, waits for the room,
and adds it to the merged contact with the same number when there is one
(opening that contact), else opens the room.

### Merged chat screen

- Route `/rooms/contact/:id` (with `?event=` and `?room=` for a jump).
  Opening a member room's own route redirects here, so notifications and
  links land in the merged view. Only the room's own page redirects, not
  its details or settings; `?single=1` and shared items keep a room on its
  own.
- App bar: the contact's avatar and name, with no subtitle. Tapping them,
  or "Chat details" in the menu, opens the chat details sheet (below).
  Before the menu, `ChatNetworkIcons`
  (`lib/pages/chat/chat_app_bar_title.dart`) shows one toggle button per
  network, the network's logo in a connected button group, ending in the
  add-chat "+". The selected button is the network the next message goes
  out on; tapping another switches to it and keeps it as the contact's
  network. A chat that is not merged shows its own network's button the same
  way, and a member room opened on its own (`?single=1`) has a network menu
  under its title that switches to the contact's other rooms.
- Composer: the hint text is the name of the network the message goes out
  on (`chat_input_row.dart`), and the send button inside the composer takes
  that network's bubble colour.
- Bubbles: with "One color per network" on (`networkBubbleColors`, the
  default),
  the user's own bubbles take the colour of the network each message went
  out on (`MergedNetwork.bubbleColor`, passed to `Message` as
  `networkColor`), so the network of every message shows at a glance. With
  it off, a message from a different network than the one before it (the
  older message above it) carries the network's name under the bubble
  instead.
- Encryption badge reflects the target room, and warns when the target is
  unencrypted while another room in the contact is encrypted.
- Chat details: a sheet titled "Chat details", "Choose a network", lists
  one row per network (its icon, its name, and the person's phone number
  there when known, else the chat's name); a row opens that room's own
  details page, as there is no merged details page. A last "Linked chats"
  row opens the manage sheet. The details page is pushed over the merged
  chat, so going back returns to the merged view with the send-via pick
  unchanged. A chat on one network opens its details directly.

### Settings

"Merged contacts" under Chat (`/rooms/settings/chat/merged_contacts`): list
of contacts (each opens the manage sheet), pending suggestions strong and
weak, a switch to turn suggestions off, and the phone number region.

The chat list shows the first suggestion as a banner under the filter
chips, with a link to the rest.

## Notifications

- Android: the conversation shortcut, the conversation channel and the
  notification ID use `contact_<id>` for a merged room
  (`notificationConversation` in `conversation.dart`), so one conversation
  bubble covers all rooms. A read room only clears the contact's
  notification once every room of the contact is read. Inline reply goes
  through SendRouter (reply in the room the notification came from).
- Windows, Linux, macOS and web notifications share the same key and the
  contact's name. A toast tap opens the room's route with the event, which
  redirects to the merged route; inline reply the same.
- Push payloads still name a room; the handler maps room -> contact. A
  notification is skipped while its room is on screen, which includes the
  merged screen of its contact (`isChatActive`).

## Android share sheet

- `AndroidShareTargets` (`lib/utils/android_share_targets.dart`) publishes
  the eight most recent chats as conversation shortcuts in the Direct Share
  category, a few seconds after a sync and only when the list changed. A
  merged contact is one shortcut, `contact_<id>`, named and pictured like
  its notification. Message notifications publish the same shortcut IDs.
- Picking a chat in the share sheet hands its shortcut ID to Dart
  (`MainActivity.kt`, `AndroidDirectShare`). `shareTargetRoute` turns
  `contact_<id>` into `/rooms/contact/<id>`, and a room ID into the room,
  or into its contact's screen when the room has since been merged. The
  shared items go to the composer's target room.

## Phases

1. **Store and list.** Store, merge/unmerge actions, one tile per contact,
   member rooms hidden. Opening the tile opens the `send_via` room with a
   room switcher in the app bar. No timeline work.
2. **Network picker and routing** on the single-room screen: picking a
   network switches which member room is shown and sent to (picking a
   network opens that room, and is kept as the contact's default).
3. **Merged timeline.** `MergedTimeline` (a `Timeline`), the safe-horizon
   history loader, per-event routing, read markers.
4. **Suggestions and notification grouping.**
5. **Fallback offer on failed sends.**

Each phase ships alone. Phase 1 and 2 give most of the daily value; phase 3
is the largest and carries the risk.

## Risks

- **History gaps** if the horizon rule is wrong: covered by unit tests on
  MergedTimeline with fake timelines (interleaved, one empty, one exhausted,
  equal timestamps).
- **Clock skew** between bridges reorders near-simultaneous messages.
  Accepted; ordering is by server timestamp.
- **Account data races** between two devices editing at once: last write
  wins per contact; a lost edit is a lost merge or rename, never lost
  messages.
- **ChatController size.** It is already large. Merging lives in
  `lib/utils/merged_contacts/` and `MergedTimeline`; the controller only
  picks the timeline, asks `SendRouter` for rooms and keeps the one-off
  network pick.
- **Upstream.** Client-only and additive, but it touches the chat list and
  controller, which upstream changes often. Keep it behind `MergedTimeline`,
  `SendRouter` and a few call sites to keep merges cheap.

## Tests

- Store: parse, drop stale rooms, one-contact-per-room, last-write-wins.
- MergedTimeline: ordering, horizon, insert/remove mapping, history request
  choice.
- SendRouter: every row of the table above.
- Suggester: phone normalisation, dismissed pairs.
- Widget: tile shows summed unread and newest preview.
- New chat: the provisioning API wrapper against a fake HTTP client
  (`test/utils/bridge_provisioning_test.dart`), the merge of the three
  sources and typed numbers (`test/utils/new_chat_people_test.dart`), and
  the result rows and network sheet (`test/widgets/new_chat_people_test.dart`).

They live in `test/utils/merged_contacts/` (store, chat list collapse,
`MergedOrder`, `MergedTimeline`, `SendRouter`, phone numbers, identifiers,
suggester, suggestion service, notification conversations) and
`test/widgets/merged_contact_tile_test.dart`. The app bar's network buttons
have no widget test. Rooms in those tests come from a client that is
never logged in (`fake_rooms.dart`), so they run without a server or the
encryption library.
