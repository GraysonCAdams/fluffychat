// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/chat_list/message_preview_cache.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

abstract class ShareItem {}

class TextShareItem extends ShareItem {
  final String value;
  TextShareItem(this.value);
}

class ContentShareItem extends ShareItem {
  final Map<String, Object?> value;
  ContentShareItem(this.value);
}

class FileShareItem extends ShareItem {
  final XFile value;
  FileShareItem(this.value);
}

/// A chat the share page sends to: one the user has, or a person without a
/// chat on the network the user picked for them.
sealed class ShareTarget {
  const ShareTarget();

  /// Identifies the row, so a tick survives a new search.
  String get key;

  /// The name the page shows, also in the "could not send" message.
  String get name;
}

/// An existing chat; a merged contact is one target.
class ChatShareTarget extends ShareTarget {
  final ExistingChat chat;
  @override
  final String name;

  const ChatShareTarget(this.chat, this.name);

  @override
  String get key => keyOf(chat);

  static String keyOf(ExistingChat chat) => switch (chat.contact) {
    final contact? => 'contact:${contact.id}',
    null => 'room:${chat.room.id}',
  };
}

/// A person with no chat yet, started on [choice]'s network on send.
class NewChatShareTarget extends ShareTarget {
  final NewChatPerson person;
  final StartChatChoice choice;

  const NewChatShareTarget(this.person, this.choice);

  @override
  String get key => keyOf(person);

  @override
  String get name => person.name;

  static String keyOf(NewChatPerson person) =>
      'person:${person.phone ?? person.email ?? person.name}';
}

/// What the page sends to each target, in this order: [files] (one event
/// each), then the forwarded [contents], then [text] as its own message.
class SharePayload {
  final List<XFile> files;
  final List<Map<String, Object?>> contents;
  final String text;

  const SharePayload({
    this.files = const [],
    this.contents = const [],
    this.text = '',
  });
}

/// How the share page reaches the network and the chats: picking a network
/// for a person, starting their chat, and sending. Widget tests replace it
/// with a fake.
class ShareDelivery {
  const ShareDelivery();

  /// Starts reading the bridges' contact lists and the phone's contacts
  /// into [sources], for the search.
  Future<void> loadSources(Client client, NewChatSources sources) =>
      sources.load(client);

  /// The network to start a chat with [person] on, from New Chat's network
  /// picker; null when the user closed it.
  Future<StartChatChoice?> pickNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) => pickStartChatNetwork(context, client, person);

  /// The room [target]'s messages go to and the route that opens its chat.
  /// For a person without a chat, starts the chat on the picked network
  /// the way New Chat does.
  Future<({Room room, String route})> resolve(
    Client client,
    ShareTarget target,
  ) async {
    switch (target) {
      case ChatShareTarget(:final chat):
        final contact = chat.contact;
        return (
          room: chat.sendRoom,
          route: contact == null
              ? '/rooms/${chat.room.id}'
              : mergedContactRoute(contact.id),
        );
      case NewChatShareTarget(:final person, :final choice):
        final directory = BridgeDirectory.forClient(client);
        if (directory == null) throw StateError('Not logged in');
        final roomId = await startBridgeChat(client, directory.api, choice);
        final contactId = await addNewChatToMergedContact(
          client,
          person,
          roomId,
        );
        final room = client.getRoomById(roomId);
        if (room == null) throw StateError('Room $roomId is not known');
        return (
          room: room,
          route: contactId == null
              ? '/rooms/$roomId'
              : mergedContactRoute(contactId),
        );
    }
  }

  /// Sends [payload] to [room] the way the composer does: files through
  /// [sendAttachments], then the text. Throws when anything was not sent.
  Future<void> send(
    BuildContext context,
    Room room,
    SharePayload payload,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!proceed || !context.mounted) {
      throw StateError('Sending to ${room.id} was cancelled');
    }
    Object? failure;
    await sendAttachments(
      room: room,
      files: payload.files,
      scaffoldMessenger: ScaffoldMessenger.of(context),
      l10n: L10n.of(context),
      onError: (error, _) => failure ??= error,
    );
    if (payload.contents.isNotEmpty || payload.text.trim().isNotEmpty) {
      if (!room.otherPartyCanReceiveMessages) {
        throw OtherPartyCanNotReceiveMessages();
      }
    }
    for (final content in payload.contents) {
      await room.sendEvent(content.copy());
    }
    if (payload.text.trim().isNotEmpty) await room.sendTextEvent(payload.text);
    if (failure case final error?) throw error;
  }
}

/// The share page: pick one or more chats, or people to start a chat with,
/// and send [items] to all of them. Shown for the Android share sheet,
/// forwarding messages and sharing from the image viewer.
class ShareScaffoldDialog extends StatefulWidget {
  final List<ShareItem> items;
  final ShareDelivery delivery;

  const ShareScaffoldDialog({
    required this.items,
    this.delivery = const ShareDelivery(),
    super.key,
  });

  @override
  State<ShareScaffoldDialog> createState() => _ShareScaffoldDialogState();
}

/// One line of the page's list.
sealed class _Line {
  const _Line();
}

class _HeaderLine extends _Line {
  final String text;
  const _HeaderLine(this.text);
}

class _MoreLine extends _Line {
  const _MoreLine();
}

class _ChatLine extends _Line {
  final ExistingChat chat;
  final _Position position;

  /// Whether the subtitle is the phone number when one is known, as in the
  /// A to Z list, rather than the last message.
  final bool preferPhone;
  const _ChatLine(this.chat, this.position, {this.preferPhone = false});
}

class _PersonLine extends _Line {
  final NewChatPerson<ExistingChat> person;
  final _Position position;
  const _PersonLine(this.person, this.position);
}

/// Where a card sits in its group, for its corners.
typedef _Position = ({bool first, bool last});

_Position _positionIn(int index, int length) =>
    (first: index == 0, last: index == length - 1);

class _ShareScaffoldDialogState extends State<ShareScaffoldDialog> {
  /// How many recent chats show before "More recent conversations", and
  /// how many more each tap on it adds.
  static const int recentCount = 5;
  static const int recentStep = 10;

  final TextEditingController _search = TextEditingController();
  late final TextEditingController _message = TextEditingController(
    text: widget.items
        .whereType<TextShareItem>()
        .map((i) => i.value)
        .join('\n'),
  );
  late final NewChatSources _sources = NewChatSources(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  /// The ticked targets, in the order they were ticked.
  final Map<String, ShareTarget> _selected = {};

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  int _recentShown = recentCount;
  bool _sending = false;

  Client get _client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.delivery.loadSources(_client, _sources);
    });
  }

  @override
  void dispose() {
    _sources.dispose();
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  bool _canSendTo(Room room) =>
      room.canSendDefaultMessages &&
      !room.isSpace &&
      room.membership == Membership.join;

  String _nameOf(ExistingChat chat, MatrixLocals locals) =>
      chat.contact?.displayName(locals) ??
      chat.room.getLocalizedDisplayname(locals);

  void _toggleChat(ExistingChat chat, String name) {
    final key = ChatShareTarget.keyOf(chat);
    setState(() {
      if (_selected.remove(key) == null) {
        _selected[key] = ChatShareTarget(chat, name);
      }
    });
  }

  Future<void> _togglePerson(NewChatPerson person) async {
    final key = NewChatShareTarget.keyOf(person);
    if (_selected.containsKey(key)) {
      setState(() => _selected.remove(key));
      return;
    }
    final choice = await widget.delivery.pickNetwork(context, _client, person);
    if (choice == null || !mounted) return;
    setState(() => _selected[key] = NewChatShareTarget(person, choice));
  }

  SharePayload get _payload => SharePayload(
    files: [
      for (final item in widget.items)
        if (item is FileShareItem) item.value,
    ],
    contents: [
      for (final item in widget.items)
        if (item is ContentShareItem) item.value,
    ],
    text: _message.text,
  );

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final client = _client;
    final payload = _payload;
    final targets = _selected.values.toList();
    setState(() => _sending = true);
    final routes = <String>[];
    final failed = <ShareTarget>[];
    for (final target in targets) {
      try {
        final resolved = await widget.delivery.resolve(client, target);
        if (!mounted) return;
        await widget.delivery.send(context, resolved.room, payload);
        routes.add(resolved.route);
        _selected.remove(target.key);
      } catch (e, s) {
        Logs().w('Unable to share to ${target.name}', e, s);
        failed.add(target);
      }
      if (!mounted) return;
    }
    setState(() => _sending = false);
    if (failed.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.notSentTo(failed.map((target) => target.name).join(', ')),
          ),
        ),
      );
      return;
    }
    while (router.canPop()) {
      router.pop();
    }
    if (routes.length == 1) {
      router.go(routes.single);
    } else {
      router.go('/rooms');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.sentToChats(routes.length))),
      );
    }
  }

  List<_Line> _restingLines(L10n l10n, MatrixLocals locals) {
    final chats = existingChatsOf(
      _client,
      _client.rooms.where(_canSendTo).toList(),
      (_) => true,
    );
    final recent = chats.take(_recentShown).toList();
    final rest = chats.skip(_recentShown).toList()
      ..sort(
        (a, b) => _nameOf(
          a,
          locals,
        ).toLowerCase().compareTo(_nameOf(b, locals).toLowerCase()),
      );
    final lines = <_Line>[];
    if (recent.isNotEmpty) {
      lines.add(_HeaderLine(l10n.recentConversations));
      for (final (i, chat) in recent.indexed) {
        lines.add(_ChatLine(chat, _positionIn(i, recent.length)));
      }
      if (rest.isNotEmpty) lines.add(const _MoreLine());
    }
    final byLetter = <String, List<ExistingChat>>{};
    for (final chat in rest) {
      final initial = _nameOf(chat, locals).trim().characters.firstOrNull;
      final letter = initial != null && _letter.hasMatch(initial)
          ? initial.toUpperCase()
          : '#';
      byLetter.putIfAbsent(letter, () => []).add(chat);
    }
    final letters = byLetter.keys.toList()
      ..sort(
        (a, b) => a == '#'
            ? 1
            : b == '#'
            ? -1
            : a.compareTo(b),
      );
    for (final letter in letters) {
      final group = byLetter[letter]!;
      lines.add(_HeaderLine(letter));
      for (final (i, chat) in group.indexed) {
        lines.add(
          _ChatLine(chat, _positionIn(i, group.length), preferPhone: true),
        );
      }
    }
    return lines;
  }

  List<_Line> _searchLines(String query, L10n l10n, MatrixLocals locals) {
    final chats = searchExistingChats(_client, query, locals, keep: _canSendTo);
    final people = _sources.people(query, [
      for (final chat in chats) chatPersonInput(chat, locals),
    ]);
    final contacts = people.where((person) => person.chat == null).toList();
    return [
      if (chats.isNotEmpty) _HeaderLine(l10n.yourChats),
      for (final (i, chat) in chats.indexed)
        _ChatLine(chat, _positionIn(i, chats.length)),
      if (contacts.isNotEmpty) _HeaderLine(l10n.contacts),
      for (final (i, person) in contacts.indexed)
        _PersonLine(person, _positionIn(i, contacts.length)),
    ];
  }

  Widget _buildLine(BuildContext context, _Line line, MatrixLocals locals) {
    final theme = Theme.of(context);
    switch (line) {
      case _HeaderLine(:final text):
        return Padding(
          key: ValueKey('share-header-$text'),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        );
      case _MoreLine():
        return Center(
          child: TextButton(
            onPressed: () => setState(() => _recentShown += recentStep),
            child: Text(L10n.of(context).moreRecentConversations),
          ),
        );
      case _ChatLine(:final chat, :final position, :final preferPhone):
        final name = _nameOf(chat, locals);
        final phone = preferPhone ? phoneOfChat(chat) : null;
        return ShareTargetCard(
          key: ValueKey(ChatShareTarget.keyOf(chat)),
          avatar: Avatar(
            mxContent: chat.contact?.avatar ?? chat.room.avatar,
            name: name,
            size: ShareTargetCard.avatarSize,
          ),
          title: name,
          subtitle: phone != null
              ? formatPhoneForDisplay(phone)
              : _preview(context, chat),
          networks: [
            for (final network in chat.networks)
              (icon: network.avatar, name: network.getLocalizedDisplayname()),
          ],
          selected: _selected.containsKey(ChatShareTarget.keyOf(chat)),
          first: position.first,
          last: position.last,
          onTap: _sending ? null : () => _toggleChat(chat, name),
        );
      case _PersonLine(:final person, :final position):
        final key = NewChatShareTarget.keyOf(person);
        final picked = _selected[key];
        final phone = person.phone;
        final networks = picked is NewChatShareTarget
            ? [NetworkRef.ofBridge(picked.choice.bridge)]
            : person.networks;
        return ShareTargetCard(
          key: ValueKey(key),
          avatar: person.typed
              ? CircleAvatar(
                  radius: ShareTargetCard.avatarSize / 2,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: const Icon(Icons.dialpad_outlined),
                )
              : Avatar(
                  mxContent: person.avatar,
                  name: person.name,
                  size: ShareTargetCard.avatarSize,
                ),
          title: person.name,
          subtitle: person.typed
              ? L10n.of(context).typedNumber
              : phone != null
              ? formatPhoneForDisplay(phone)
              : person.email ??
                    person.networks.map((network) => network.name).join(', '),
          networks: [
            for (final network in networks)
              (icon: network.icon, name: network.name),
          ],
          selected: picked != null,
          first: position.first,
          last: position.last,
          onTap: _sending ? null : () => _togglePerson(person),
        );
    }
  }

  /// The chat's last message as the chat list previews it, with "You: " or
  /// the sender's name in front where the chat list shows one.
  String _preview(BuildContext context, ExistingChat chat) {
    final l10n = L10n.of(context);
    final event = chat.contact?.lastEvent ?? chat.room.lastEvent;
    if (event == null) return l10n.noMessagesYet;
    final body = MessagePreviewCache.localizedBody(
      event,
      l10n,
      MatrixLocals(l10n),
    ).trim().replaceAll('\n', ' ');
    final room = event.room;
    if (event.senderId == room.client.userID) {
      return l10n.senderMessage(l10n.you, body);
    }
    if (room.directChatMatrixID == event.senderId) return body;
    return l10n.senderMessage(
      event.senderFromMemoryOrFallback.calcDisplayname(),
      body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    final query = _search.text.trim();
    final lines = query.isEmpty
        ? _restingLines(l10n, locals)
        : _searchLines(query, l10n, locals);
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: Center(
          child: BackButton(onPressed: () => Navigator.of(context).pop()),
        ),
        title: Text(l10n.share),
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                hintText: l10n.shareSearchHint,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                ),
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.clear,
                        icon: const Icon(Icons.clear_outlined),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: lines.length,
              itemBuilder: (context, i) =>
                  _buildLine(context, lines[i], locals),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ShareBottomBar(
        items: widget.items,
        message: _message,
        count: _selected.length,
        sending: _sending,
        onSend: _send,
      ),
    );
  }
}

/// One chat or person on the share page: a rounded card in a group of
/// cards, with the avatar, name, second line, the networks as grey icons
/// and a round tick.
class ShareTargetCard extends StatelessWidget {
  static const double avatarSize = 44;
  static const double outerRadius = 22;
  static const double innerRadius = 6;
  static const double gap = 3;

  final Widget avatar;
  final String title;
  final String subtitle;
  final List<({Uri? icon, String name})> networks;
  final bool selected;

  /// Whether the card starts or ends its group, which rounds that side.
  final bool first;
  final bool last;
  final void Function()? onTap;

  const ShareTargetCard({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.networks,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? outerRadius : innerRadius),
      bottom: Radius.circular(last ? outerRadius : innerRadius),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, last ? 0 : gap),
      child: Semantics(
        checked: selected,
        child: Material(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainer,
          borderRadius: radius,
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  spacing: 16,
                  children: [
                    avatar,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (networks.isNotEmpty)
                      MonochromeNetworkIcons.icons(icons: networks),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixed bar under the list: what is shared (thumbnails of files, or
/// the number of forwarded messages), the message field and the send
/// button.
class _ShareBottomBar extends StatelessWidget {
  final List<ShareItem> items;
  final TextEditingController message;
  final int count;
  final bool sending;
  final void Function() onSend;

  const _ShareBottomBar({
    required this.items,
    required this.message,
    required this.count,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final files = [
      for (final item in items)
        if (item is FileShareItem) item.value,
    ];
    final forwarded = items.whereType<ContentShareItem>().length;
    final sharesText = items.any((item) => item is TextShareItem);
    final allImages = files.every(
      (file) => (file.mimeType ?? lookupMimeType(file.path) ?? '').startsWith(
        'image/',
      ),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (files.isNotEmpty)
                Row(
                  spacing: 8,
                  children: [
                    for (final file in files.take(4)) _Thumbnail(file),
                    Expanded(
                      child: Text(
                        allImages
                            ? l10n.countPhotos(files.length)
                            : l10n.countSharedFiles(files.length),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              if (forwarded > 0)
                Row(
                  spacing: 8,
                  children: [
                    Icon(
                      Icons.forward_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      l10n.countForwardedMessages(forwarded),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              TextField(
                controller: message,
                minLines: 1,
                maxLines: 4,
                enabled: !sending,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  hintText: sharesText ? null : l10n.addAMessage,
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: count == 0 || sending ? null : onSend,
                child: sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(count == 0 ? l10n.send : l10n.sendToChats(count)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small rounded preview of a shared file: the picture for an image,
/// else a file icon.
class _Thumbnail extends StatefulWidget {
  final XFile file;

  const _Thumbnail(this.file);

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  static const double size = 48;

  /// Read once: the bar rebuilds on every keystroke in the message field.
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;
    final mime = file.mimeType ?? lookupMimeType(file.path) ?? '';
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        mime.startsWith('image/')
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: size,
        child: !mime.startsWith('image/')
            ? placeholder
            : FutureBuilder(
                future: _bytes,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) return placeholder;
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                    errorBuilder: (_, _, _) => placeholder,
                  );
                },
              ),
      ),
    );
  }
}
