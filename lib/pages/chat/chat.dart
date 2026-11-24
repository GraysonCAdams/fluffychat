// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
import 'package:fluffychat/pages/chat/gallery_picker/gallery_picker_page.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/pages/chat/utils/web_file_to_x_file.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/clipboard_gif.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/media_adaptation.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/merged_timeline.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/ogg_opus_remuxer.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/pasted_file_type.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/utils/scheduled_messages.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/utils/windows_clipboard.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:universal_html/universal_html.dart' as web;

import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import '../../utils/stream_extension.dart';
import 'send_location_dialog.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final Timeline? timeline;
  final String? action;

  /// Set to show a merged contact: all of its rooms in one timeline. Then
  /// [roomId] is unused.
  final String? contactId;

  /// The room [eventId] is in, when known, so a merged timeline opens it
  /// there without asking each room.
  final String? eventRoomId;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
    this.timeline,
    this.action,
    this.contactId,
    this.eventRoomId,
  });

  @override
  Widget build(BuildContext context) {
    final contactId = this.contactId;
    if (contactId != null) return _buildMerged(context, contactId);
    final room =
        timeline?.room ?? Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_${eventId}_$action'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
      timeline: timeline,
      action: action,
    );
  }

  Widget _buildMerged(BuildContext context, String contactId) {
    final client = Matrix.of(context).client;
    final store = MergedContactsStore.forClient(client);
    return ValueListenableBuilder(
      valueListenable: store.revision,
      builder: (context, _, _) {
        final entry = store.contactById(contactId);
        final contact = entry == null
            ? null
            : MergedContact.resolve(client, entry);
        if (contact == null) {
          // Until the first sync the contacts may not be known yet.
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: client.prevBatch == null
                  ? const CircularProgressIndicator.adaptive()
                  : Text(L10n.of(context).contactWasUnmerged),
            ),
          );
        }
        return ChatPageWithRoom(
          // The page stays the same while the contact's default network
          // changes, which only changes widget.room.
          key: Key('chat_page_contact_${contactId}_${eventId}_$action'),
          room: contact.sendViaRoom,
          contactId: contactId,
          shareItems: shareItems,
          eventId: eventId,
          eventRoomId: eventRoomId,
          action: action,
        );
      },
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  /// The room shown, or for a merged contact its default room.
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final Timeline? timeline;
  final String? action;

  /// Set when this shows a merged contact (see [ChatPage.contactId]).
  final String? contactId;
  final String? eventRoomId;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
    this.timeline,
    this.action,
    this.contactId,
    this.eventRoomId,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => isMerged
      ? mergedContact?.roomById(roomId) ?? widget.room
      : sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? activeThreadId;

  late final Set<String> bigEmojis;

  /// The event the "new messages" line is drawn at, or empty for none. A
  /// merged contact's is only known once its timeline has loaded.
  String readMarkerEventId = '';

  /// The room new messages go to. For a merged contact that is the target
  /// network, which the send-via button and the contact's send mode change, so
  /// everything reading [room] (encryption, permissions, the composer)
  /// follows the target.
  String get roomId => isMerged ? sendRouter.newMessageRoomId : widget.room.id;

  /// Whether this screen shows a merged contact's rooms in one timeline.
  bool get isMerged => widget.contactId != null;

  (int, MergedContact?)? _mergedContact;

  /// The merged contact shown, or the one the shown room belongs to. Kept
  /// until the contacts change: [room] asks for it on every read, and
  /// resolving rooms walks the account's room list.
  MergedContact? get mergedContact {
    final client = widget.room.client;
    final revision = MergedContactsStore.forClient(client).revision.value;
    final cached = _mergedContact;
    if (cached != null && cached.$1 == revision) return cached.$2;
    final contactId = widget.contactId;
    final MergedContact? contact;
    if (contactId == null) {
      contact = MergedContact.ofRoom(client, widget.room.id);
    } else {
      final entry = MergedContactsStore.forClient(
        client,
      ).contactById(contactId);
      contact = entry == null ? null : MergedContact.resolve(client, entry);
    }
    _mergedContact = (revision, contact);
    return contact;
  }

  /// A network picked on the send-via button for the next message only.
  String? _oneOffRoomId;

  /// Decides where everything sent from this screen goes (see SendRouter).
  /// A single room sends everything new to itself. A merged contact sends
  /// to the one-off pick, else per its send mode.
  SendRouter get sendRouter {
    final contact = isMerged ? mergedContact : null;
    if (contact == null) return SendRouter.single(widget.room.id);
    return SendRouter.contact(
      contact.entry,
      lastReceivedRoomId: contact.lastReceivedRoom?.id,
      oneOffRoomId: _oneOffRoomId,
    );
  }

  /// Where drafts are kept: per contact for a merged contact, so the draft
  /// survives switching networks.
  String get _draftKey => isMerged
      ? 'draft_contact_${widget.contactId}'
      : 'draft_${widget.room.id}';

  /// A new message left the composer: a network picked for it was for that
  /// message only.
  void _afterNewMessage() {
    if (_oneOffRoomId != null) setState(() => _oneOffRoomId = null);
  }

  /// The room of the thread being shown, found from its root message.
  String? get activeThreadRoomId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
            .firstWhereOrNull((event) => event.eventId == threadId)
            ?.roomId ??
        room.id;
  }

  /// Where the composer sends, and whether that is locked to the network of
  /// a message being edited, replied to or answered in a thread.
  SendTarget get composerTarget => sendRouter.composerTarget(
    editRoomId: editEvent?.roomId,
    replyRoomId: replyEvent?.roomId,
    threadRoomId: activeThreadRoomId,
  );

  /// The room the composer's next message, attachment, voice message,
  /// sticker, location or poll goes to.
  Room get composerRoom => _resolveRoom(composerTarget.roomId);

  /// The room [action] on [event] goes to: always the event's own room.
  Room roomForEvent(Event event, SendAction action) {
    final roomId = sendRouter.route(action, eventRoomId: event.roomId);
    return roomId == event.room.id ? event.room : _resolveRoom(roomId);
  }

  Room _resolveRoom(String roomId) =>
      roomId == room.id ? room : sendingClient.getRoomById(roomId) ?? room;

  /// The room typing notifications were last sent to, so they stop there
  /// even when the composer's target has moved on.
  Room? _typingRoom;

  /// The send-via button picked [roomId] for the next message. A merged
  /// contact just changes the target; a single room shown on its own
  /// switches to the contact's other room.
  void pickSendViaRoom(String roomId) {
    if (isMerged) {
      setState(() => _oneOffRoomId = roomId);
      return;
    }
    context.go('/rooms/$roomId?single=1');
  }

  (int, String, List<MergedNetwork>)? _mergedNetworks;

  /// The networks of this chat's merged contact for the send-via button, or
  /// null when the chat is not merged. Kept until the contacts change, as
  /// finding each room's space walks every room of the account.
  List<MergedNetwork>? mergedNetworks(MatrixLocals locals) {
    final contact = mergedContact;
    if (contact == null) return null;
    final revision = MergedContactsStore.forClient(room.client).revision.value;
    final cached = _mergedNetworks;
    if (cached != null && cached.$1 == revision && cached.$2 == contact.id) {
      return cached.$3;
    }
    final networks = MergedNetwork.of(contact, locals);
    _mergedNetworks = (revision, contact.id, networks);
    return networks;
  }

  /// The merged contact's default network.
  String? get mergedDefaultRoomId => mergedContact?.sendViaRoom.id;

  /// Makes [roomId] the merged contact's default network.
  Future<void> setMergedSendVia(String roomId) async {
    final contact = mergedContact;
    if (contact == null) return;
    await MergedContactsStore.forClient(
      room.client,
    ).setSendVia(contact.id, roomId);
  }

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;

  final GlobalKey inputBarKey = GlobalKey();

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited(_) => setState(() => dragging = false);

  Future<void> onDragDone(DropDoneDetails details) async {
    setState(() => dragging = false);
    if (details.files.isEmpty) return;

    addPendingAttachments(details.files);
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  /// Whether the add button's attachment panel is open in place of the
  /// keyboard.
  bool showAttachmentPanel = false;

  /// Files staged in the composer, sent ahead of the text on the next send.
  final List<XFile> pendingAttachments = [];

  /// Whether the staged files were picked to send at full quality.
  bool _pendingAttachmentsInHd = false;

  void addPendingAttachments(Iterable<XFile> files) =>
      setState(() => pendingAttachments.addAll(files));

  void removePendingAttachment(XFile file) =>
      setState(() => pendingAttachments.remove(file));

  void toggleAttachmentPanel() {
    if (showAttachmentPanel) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() {
      showAttachmentPanel = !showAttachmentPanel;
      showEmojiPicker = false;
    });
  }

  void _onAttachmentError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toLocalizedString(context))));
  }

  /// Picks files and stages them in the composer.
  Future<void> pickFilesToComposer({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty || !mounted) return;
    addPendingAttachments(files);
  }

  /// Opens the full-screen camera and gallery picker and stages what it
  /// returns in the composer, with its caption as the message text.
  Future<void> openGalleryPicker() async {
    final result = await showGalleryPicker(
      context,
      recipientName: room.getLocalizedDisplayname(),
    );
    if (result == null || !mounted) return;
    setState(() {
      showAttachmentPanel = false;
      pendingAttachments.addAll(result.files);
      _pendingAttachmentsInHd = result.hd;
    });
    final caption = result.caption.trim();
    if (caption.isNotEmpty && sendController.text.trim().isEmpty) {
      sendController.text = caption;
    }
  }

  int emojiPickerInitialTab = 0;

  final UndoHistoryController undoController = UndoHistoryController();

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  Future<void> recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  Future<void> joinChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await room.join(waitForSync: true);
      },
    );
    if (!mounted) return;
    if (success.error != null) return;
    if (room.isSpace) {
      context.go('/rooms?spaceId=${room.id}');
      return;
    }
    await _tryLoadTimeline();
  }

  Future<void> leaveChat() async {
    if (room.membership == .invite) {
      final blockConsent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).declineInvitation,
        message: L10n.of(context).doYouAlsoWantToBlock,
        cancelLabel: L10n.of(context).decline,
        okLabel: L10n.of(context).declineAndBlock,
        isDestructive: true,
      );
      if (blockConsent == null) return;
      if (!mounted) return;
      if (blockConsent == .ok) {
        final inviteEvent = room.getState(
          EventTypes.RoomMember,
          room.client.userID!,
        );
        context.go(
          '/rooms/settings/security/ignorelist',
          extra: inviteEvent?.senderId,
        );
        return;
      }
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (!mounted) return;
    if (success.error != null) return;
    context.go('/rooms');
  }

  Future<void> requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  Future<void> requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0) {
      // Only rebuild when the flag actually flips; this listener runs on
      // every scroll frame.
      if (_scrolledUp == false) setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString(_draftKey);
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  Future<void> _shareItems() async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final target = composerRoom;
    final proceed = await showTrustUserInRoomDialog(context, target);
    if (!mounted || !proceed) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) target.sendTextEvent(item.value);
      if (item is ContentShareItem) target.sendEvent(item.value.copy());
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    addPendingAttachments(files);
  }

  void _toggleEmojiPickerTab(int tab) {
    if (showEmojiPicker && emojiPickerInitialTab == tab) {
      emojiPickerAction();
    } else if (showEmojiPicker) {
      // Already open on a different tab — close and reopen on the new tab
      setState(() {
        showEmojiPicker = false;
        emojiPickerInitialTab = tab;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        emojiPickerAction();
      });
    } else {
      emojiPickerInitialTab = tab;
      emojiPickerAction();
    }
  }

  void _wrapSelectedText(String prefix, String suffix) {
    final selection = sendController.selection;
    final text = sendController.text;
    final selectedText = selection.textInside(text);

    final replacement = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    final cursorOffset = selectedText.isEmpty
        ? selection.start + prefix.length
        : selection.start + replacement.length;

    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.arrowUp &&
        !PlatformInfos.isMobile &&
        editEvent == null &&
        replyEvent == null &&
        sendController.text.isEmpty) {
      _editLastSentMessage();
      return KeyEventResult.handled;
    }

    if (evt is KeyDownEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      if (evt.logicalKey == LogicalKeyboardKey.keyB) {
        _wrapSelectedText('**', '**');
        return KeyEventResult.handled;
      }
      if (evt.logicalKey == LogicalKeyboardKey.keyI) {
        _wrapSelectedText('*', '*');
        return KeyEventResult.handled;
      }
      if (evt.logicalKey == LogicalKeyboardKey.keyE) {
        _toggleEmojiPickerTab(0);
        return KeyEventResult.handled;
      }
      if (evt.logicalKey == LogicalKeyboardKey.keyS) {
        _toggleEmojiPickerTab(1);
        return KeyEventResult.handled;
      }
      if (evt.logicalKey == LogicalKeyboardKey.keyY) {
        undoController.redo();
        return KeyEventResult.handled;
      }
    }

    if (evt is KeyDownEvent && evt.logicalKey == LogicalKeyboardKey.escape) {
      if (showEmojiPicker) {
        hideEmojiPicker();
        inputFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (editEvent != null) {
        _cancelEditWithConfirmation();
        return KeyEventResult.handled;
      }
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareItems();
      _checkMatrixRtcCallSupport();
      if (widget.action == 'call') {
        Matrix.of(context).activeCallRoomId.value = room.id;
      }
    });
    web.window.addEventListener('paste', _handleClipboardFilePasteWeb);
    HardwareKeyboard.instance.addHandler(_escapeClearsSelection);

    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    bigEmojis = defaultEmojiSet.fold(
      <String>{},
      (emojis, category) =>
          emojis..addAll(category.emoji.map((emoji) => emoji.emoji)),
    );

    sendingClient = Matrix.of(context).client;
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    if (!isMerged) {
      readMarkerEventId = room.hasNewMessages
          ? lastEventThreadId ?? room.fullyRead
          : '';
    }
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
  }

  Future<void> _checkMatrixRtcCallSupport() async {
    try {
      final urls = await room.client.getLiveKitServiceUrls();
      if (urls.isEmpty) return;
      setState(() {
        supportLiveKitCalls = true;
      });
    } catch (e) {
      Logs().d('Unable to check MatrixRTC call support', e);
    }
  }

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  Future<void> _tryLoadTimeline() async {
    if (room.membership == .invite) return;

    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      final timeline = this.timeline;
      if (timeline is MergedTimeline) {
        final contact = mergedContact;
        readMarkerEventId =
            timeline.readMarkerEventId({
              for (final room in contact?.rooms ?? const <Room>[])
                if (room.hasNewMessages) room.id: room.fullyRead,
            }) ??
            '';
      }
      // We launched the chat with a given initial event ID:
      if (initialEventId != null) {
        scrollToEventId(initialEventId, openThread: true);
        return;
      }

      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      // Read marker is existing but not found in first events. Try a single
      // requestHistory call before opening timeline on event context:
      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      // Mark room as read on first visit if requirements are fulfilled
      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  String? animateInEventId;

  Future<void> _insert(int index) async {
    if (index > 0) return;
    final firstEvent = timeline?.events.firstOrNull;
    final eventId = firstEvent?.transactionId ?? firstEvent?.eventId;
    animateInEventId = eventId;
    await Future.delayed(FluffyThemes.animationDuration);
    if (animateInEventId == eventId) animateInEventId = null;
  }

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  Future<void> _getTimeline({String? eventContextId}) async {
    final matrix = Matrix.of(context);
    await matrix.client.roomsLoading;
    await matrix.client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixIdStrict() ||
            eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    final contact = isMerged ? mergedContact : null;
    try {
      timeline?.cancelSubscriptions();
      timeline =
          widget.timeline ??
          (contact != null
              ? await MergedTimeline.open(
                  contact.rooms,
                  onUpdate: updateView,
                  onInsert: _insert,
                  eventContextId: eventContextId,
                  eventContextRoomId: eventContextId == widget.eventId
                      ? widget.eventRoomId
                      : null,
                )
              : await room.getTimeline(
                  onUpdate: updateView,
                  onInsert: _insert,
                  eventContextId: eventContextId,
                ));
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      if (!mounted) return;
      timeline = contact != null
          ? await MergedTimeline.open(contact.rooms, onUpdate: updateView)
          : await room.getTimeline(onUpdate: updateView);
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
    timeline!.requestKeys(onlineKeyBackupOnly: false);
    for (final room in contact?.rooms ?? [room]) {
      if (room.markedUnread) room.markUnread(false);
    }

    return;
  }

  String? scrollToEventIdMarker;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
  }

  String? _setReadMarkerEventId;

  void setReadMarker({String? eventId}) {
    // Do not send read markers when app is not in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline is MergedTimeline) {
      _setMergedReadMarkers(timeline, eventId);
      return;
    }

    final setOnLatestEvent = eventId == null;

    // We only set read marker if we are at the bottom
    if (_scrolledUp && setOnLatestEvent) return;

    // We do not set read marker if we offer user the scroll up banner
    if (scrollUpBannerEventId != null) return;

    // We do not set read marker if timeline is empty
    if (timeline == null || timeline.events.isEmpty) return;

    // Do not set read marker on rtc notification while call is active. This
    // mutes callkit.
    if (room.hasActiveMatrixRtcCall &&
        timeline.events.first.type == RtcNotificationContent.eventType) {
      return;
    }

    eventId ??= timeline.events.firstWhereOrNull((event) {
      if (event.eventId == room.lastEvent?.eventId) return true;
      if (room.client.pushruleEvaluator.match(event).notify) {
        return true;
      }
      final original = event.originalSource;
      if (original != null &&
          room.client.pushruleEvaluator
              .match(Event.fromMatrixEvent(original, room))
              .notify) {
        return true;
      }
      return false;
    })?.eventId;

    if (setOnLatestEvent && (room.hasNewMessages || room.isUnread)) {
      eventId ??=
          room.lastEvent?.eventId ?? timeline.events.firstOrNull?.eventId;
    }

    // There is no event we could place a read marker
    if (eventId == null) return;

    // This is a sending event, we do not set a readmarker yet
    if (eventId.isValidMatrixIdStrict() == false) return;

    // We are already setting a read marker on this event
    if (_setReadMarkerEventId == eventId) return;

    // Already set a read marker on this event
    if (room.fullyRead == eventId && !setOnLatestEvent) return;

    // Set a readmarker on a specific event, not latest, but room is not unread
    // at all.
    if (setOnLatestEvent &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    Logs().d('Set read marker...', eventId);
    _setReadMarkerEventId = eventId;
    // ignore: unawaited_futures
    timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .whenComplete(() {
          if (_setReadMarkerEventId == eventId) _setReadMarkerEventId = null;
        });
  }

  /// Read markers in progress per room of a merged contact.
  final Map<String, String> _mergedReadMarkers = {};

  /// A merged contact's rooms are each marked read up to their own newest
  /// shown event (or [eventId], in its own room only). Same conditions as
  /// for one room: at the bottom, no jump banner, only rooms with something
  /// unread.
  void _setMergedReadMarkers(MergedTimeline timeline, String? eventId) {
    if (eventId == null && _scrolledUp) return;
    if (scrollUpBannerEventId != null) return;
    final targets = <Timeline, Event>{};
    if (eventId != null) {
      final event = timeline.events.firstWhereOrNull(
        (e) => e.eventId == eventId,
      );
      final child = event == null ? null : timeline.childOf(event);
      if (event != null && child != null) targets[child] = event;
    } else {
      targets.addAll(timeline.newestShownPerRoom);
    }
    for (final MapEntry(key: child, value: shown) in targets.entries) {
      final room = child.room;
      // An unread reaction is newer than the newest shown message, and a
      // receipt on that message would leave the reaction unread.
      final reaction = eventId == null && room.hasUnreadReaction
          ? room.lastEvent
          : null;
      final event = reaction ?? shown;
      if (!event.eventId.isValidMatrixIdStrict()) continue;
      if (eventId == null &&
          !room.hasNewMessages &&
          room.notificationCount == 0) {
        continue;
      }
      if (room.fullyRead == event.eventId) continue;
      if (_mergedReadMarkers[room.id] == event.eventId) continue;
      _mergedReadMarkers[room.id] = event.eventId;
      child
          .setReadMarker(
            eventId: event.eventId,
            public: AppSettings.sendPublicReadReceipts.value,
          )
          .whenComplete(() {
            if (_mergedReadMarkers[room.id] == event.eventId) {
              _mergedReadMarkers.remove(room.id);
            }
          });
    }
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    _storeInputTimeoutTimer?.cancel();
    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    sendController.dispose();
    scrollController.dispose();
    inputFocus.removeListener(_inputFocusListener);
    inputFocus.dispose();
    _emojiPanelWatcher?.cancel();
    _displayChatDetailsColumn.dispose();
    inputBarHeight.dispose();
    inputTextIsEmpty.dispose();
    web.window.removeEventListener('paste', _handleClipboardFilePasteWeb);
    HardwareKeyboard.instance.removeHandler(_escapeClearsSelection);
    undoController.dispose();
    if (currentlyTyping) _typingRoom?.setTyping(false);
    MxcImage.clearCache(widget.room.id);
    super.dispose();
  }

  TextEditingController sendController = TextEditingController();

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      _typingRoom?.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  /// Offers scheduling for the typed message and the list of scheduled ones.
  Future<void> openSendOptions() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!await room.client.canScheduleMessages) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.scheduledMessagesUnsupported)),
      );
      return;
    }
    if (!mounted) return;
    final action = await showModalActionPopup<bool>(
      context: context,
      actions: [
        if (sendController.text.trim().isNotEmpty)
          AdaptiveModalAction(
            value: true,
            label: l10n.scheduleMessage,
            icon: const Icon(Icons.schedule_send_outlined),
          ),
        AdaptiveModalAction(
          value: false,
          label: l10n.scheduledMessages,
          icon: const Icon(Icons.pending_actions_outlined),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action) {
      await _scheduleTypedMessage();
    } else {
      await _showScheduledMessages();
    }
  }

  Future<void> _scheduleTypedMessage() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final sendAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final text = sendController.text;
    final store = Matrix.of(context).store;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => composerRoom.scheduleTextMessage(store, text, sendAt),
    );
    if (result.error != null || !mounted) return;
    store.remove(_draftKey);
    setState(() {
      sendController.clear();
      inputTextIsEmpty.value = true;
    });
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.messageScheduledFor(DateFormat.yMMMd().add_jm().format(sendAt)),
        ),
      ),
    );
  }

  Future<void> _showScheduledMessages() async {
    final l10n = L10n.of(context);
    final store = Matrix.of(context).store;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.client.scheduledMessages(store, roomId: roomId),
    );
    final messages = result.result;
    if (messages == null || !mounted) return;
    if (messages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noScheduledMessages)));
      return;
    }
    final picked = await showModalActionPopup<ScheduledMessage>(
      context: context,
      title: l10n.scheduledMessages,
      actions: [
        for (final message in messages)
          AdaptiveModalAction(
            value: message,
            label:
                '${DateFormat.MMMd().add_jm().format(message.sendAt)}: '
                '${message.text}',
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final sendNow = await showModalActionPopup<bool>(
      context: context,
      title: picked.text,
      actions: [
        AdaptiveModalAction(value: true, label: l10n.sendNow),
        AdaptiveModalAction(
          value: false,
          label: l10n.cancel,
          isDestructive: true,
        ),
      ],
    );
    if (sendNow == null || !mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => sendNow
          ? room.client.sendScheduledMessageNow(store, picked.delayId)
          : room.client.cancelScheduledMessage(store, picked.delayId),
    );
  }

  Future<void> send() async {
    // Taken once: the reply, edit or picked network can change while the
    // dialogs below are open, and the message must go where the composer
    // showed when the user pressed send.
    final target = composerRoom;
    final proceed = await showTrustUserInRoomDialog(context, target);
    if (!mounted || !proceed) return;
    if (pendingAttachments.isNotEmpty) {
      final files = List.of(pendingAttachments);
      final hd = _pendingAttachmentsInHd;
      setState(() {
        pendingAttachments.clear();
        _pendingAttachmentsInHd = false;
        showAttachmentPanel = false;
      });
      await sendAttachments(
        room: target,
        files: files,
        compress: !hd,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
        scaffoldMessenger: ScaffoldMessenger.of(context),
        l10n: L10n.of(context),
        onError: _onAttachmentError,
      );
      if (!mounted) return;
    }
    if (sendController.text.trim().isEmpty) return;
    _storeInputTimeoutTimer?.cancel();
    final prefs = Matrix.of(context).store;
    prefs.remove(_draftKey);
    var parseCommands = true;

    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      final l10n = L10n.of(context);
      final dialogResult = await showOkCancelAlertDialog(
        context: context,
        title: l10n.commandInvalid,
        message: l10n.commandMissing(commandMatch[0]!),
        okLabel: l10n.sendAsText,
        cancelLabel: l10n.cancel,
      );
      if (dialogResult == OkCancelResult.cancel) return;
      parseCommands = false;
    }

    if (currentlyTyping) {
      typingCoolDown?.cancel();
      currentlyTyping = false;
      _typingRoom?.setTyping(false);
    }

    // ignore: unawaited_futures
    target.sendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      editEventId: editEvent?.eventId,
      parseCommands: parseCommands,
      threadRootEventId: activeThreadId,
    );
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );

    setState(() {
      sendController.text = pendingText;
      inputTextIsEmpty.value = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
    _afterNewMessage();
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    if (!mounted) return;
    addPendingAttachments(files);
  }

  Future<void> sendImageFromClipBoard(Uint8List? image) async {
    if (image == null) return;
    addPendingAttachments([pastedImageData(image)]);
  }

  Future<void> openGalleryAction() async {
    inputFocus.unfocus();
    final files = await ImagePicker().pickMultipleMedia(
      requestFullMetadata: false,
    );
    if (files.isEmpty) return;
    if (!mounted) return;

    addPendingAttachments(files);
  }

  Future<void> openCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    if (!mounted) return;

    addPendingAttachments([file]);
  }

  Future<void> _handleClipboardFilePasteWeb(web.Event event) async {
    if (event is! web.ClipboardEvent) return;

    final clipboardFiles = event.clipboardData?.files;
    final length = clipboardFiles?.length ?? 0;
    if (clipboardFiles == null || length < 1) return;

    // Browser will clear clipboardData when we await!
    // We MUST extract the files synchronously first.
    final localFiles = clipboardFiles.toList();

    if (localFiles.isEmpty) return;

    event.preventDefault();
    event.stopPropagation();

    final xFilesResult = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Convert one after another seems to be more stable
        final xFiles = <XFile>[];
        for (final file in localFiles) {
          xFiles.add(await webToXFile(file));
        }
        return xFiles;
      },
    );
    final xFiles = xFilesResult.result;
    if (xFiles == null || xFiles.isEmpty) return;

    if (!mounted) return;
    addPendingAttachments(xFiles);
  }

  /// Offers the GIF linked from the clipboard for sending, returning false
  /// when the clipboard holds no such GIF.
  Future<bool> _pasteClipboardGif() async {
    final gif = await clipboardLinkedGif();
    if (gif == null) return false;
    if (!mounted) return true;
    addPendingAttachments([gif]);
    return true;
  }

  Future<void> _handleClipboardImagePaste() async {
    if (await _pasteClipboardGif()) return;
    final paths = await Pasteboard.files();
    if (paths.isNotEmpty) {
      final files = await Future.wait(paths.map(pastedFile));
      if (!mounted) return;
      addPendingAttachments(files);
      return;
    }
    final image = await Pasteboard.image;
    if (image != null) {
      await sendImageFromClipBoard(image);
      return;
    }
    // No image in clipboard — fall back to pasting text
    final textData = await Clipboard.getData('text/plain');
    if (textData?.text != null) {
      final selection = sendController.selection;
      final text = sendController.text;
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        textData!.text!,
      );
      sendController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + textData.text!.length,
        ),
      );
      onInputBarChanged(sendController.text);
    }
  }

  Future<void> openVideoCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;
    if (!mounted) return;

    addPendingAttachments([file]);
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    final target = composerRoom;
    final proceed = await showTrustUserInRoomDialog(context, target);
    if (!mounted || !proceed) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: () => XFile(path).readAsBytes(),
    );
    var bytes = bytesResult.result;
    if (bytes == null) return;

    // Android's MediaMuxer writes broken Ogg containers:
    if (PlatformInfos.isAndroid && fileName.endsWith('.ogg')) {
      bytes = remuxOggOpus(bytes);
    }

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final extension = mimeType == null ? null : extensionFromMime(mimeType);
    if (extension != null) {
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName,
      mimeType: mimeType,
    );

    try {
      // Voice messages are only checked against the room's bridge: one it
      // would refuse, or over its size limit, is not sent.
      await adaptMediaForRoom(
        features: await RoomFeatures.load(target),
        file: file,
        msgType: CapabilityMsgType.voice,
        allowFileFallback: false,
      );
      await target.sendFileEvent(
        file,
        inReplyTo: replyEvent,
        threadRootEventId: activeThreadId,
        extraContent: {
          'info': {...file.info, 'duration': duration},
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration,
            'waveform': waveform,
          },
        },
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      return;
    }
    setState(() {
      replyEvent = null;
    });
    _afterNewMessage();
    return;
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() {
      showEmojiPicker = !showEmojiPicker;
      showAttachmentPanel = false;
    });
  }

  void _inputFocusListener() {
    if ((showEmojiPicker || showAttachmentPanel) && inputFocus.hasFocus) {
      setState(() {
        showEmojiPicker = false;
        showAttachmentPanel = false;
      });
    }
    if (PlatformInfos.isWindows) _watchEmojiPanel(inputFocus.hasFocus);
  }

  Timer? _emojiPanelWatcher;

  /// The Windows emoji panel (Win+.) only copies a picked GIF to the
  /// clipboard, since Flutter's text field cannot take it directly. While the
  /// composer has focus, a GIF the panel copies is offered for sending as if
  /// the user had pasted it.
  void _watchEmojiPanel(bool composerFocused) {
    _emojiPanelWatcher?.cancel();
    _emojiPanelWatcher = null;
    if (!composerFocused) return;
    var sequence = WindowsClipboard.sequenceNumber;
    _emojiPanelWatcher = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final current = WindowsClipboard.sequenceNumber;
      if (current == sequence) return;
      sequence = current;
      if (WindowsClipboard.holdsEmojiPanelContent) {
        _pasteClipboardGif();
      }
    });
  }

  Future<void> sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: composerRoom),
    );
  }

  String _getSelectedEventString() {
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first.getDisplayEvent(timeline!).body;
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event.getDisplayEvent(timeline!).body;
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  Future<void> reportEventAction() async {
    final event = selectedEvents.single;
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    final reason = await showTextInputDialog(
      context: context,
      title: l10n.whyDoYouWantToReportThis,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.reason,
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).client.reportEvent(event.roomId!, event.eventId, reason: reason),
    );
    if (result.error != null) return;
    if (!mounted) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.contentHasBeenReported)),
    );
  }

  Future<void> deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  Future<void> redactEventsAction() async {
    final reasonInput = selectedEvents.any((event) => event.status.isSent)
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
          )
        : null;
    if (reasonInput == null) return;
    final reason = reasonInput.isEmpty ? null : reasonInput;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = selectedEvents.length;
        for (final (i, event) in selectedEvents.indexed) {
          onProgress(i / count);
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = currentRoomBundle.firstWhere(
                (cl) => selectedEvents.first.senderId == cl!.userID,
                orElse: () => null,
              );
              if (client == null) {
                return;
              }
              final room = client.getRoomById(
                sendRouter.route(
                  SendAction.redaction,
                  eventRoomId: event.roomId,
                ),
              )!;
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
        }
      },
    );
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    final clients = Matrix.of(context).currentBundle;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !(clients!.any((cl) => event.senderId == cl!.userID))) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !roomForEvent(
          selectedEvents.single,
          SendAction.pin,
        ).canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (cl) => selectedEvents.first.senderId == cl!.userID,
    );
  }

  Future<void> forwardEventsAction() async {
    if (selectedEvents.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      selectedEvents,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            .map((event) => ContentShareItem(event.content.copy()))
            .toList(),
      ),
    );
    if (!mounted) return;
    setState(() => selectedEvents.clear());
  }

  /// The room a failed [event] can be sent through instead: in a merged
  /// contact with the fallback offer turned on, a plain message (not an
  /// answer to another message) goes to the next network. Null for no
  /// offer.
  Room? fallbackRoomFor(Event event) {
    if (!isMerged || event.status != EventStatus.error) return null;
    if (event.type != EventTypes.Message ||
        !{
          MessageTypes.Text,
          MessageTypes.Emote,
          MessageTypes.Notice,
        }.contains(event.messageType)) {
      return null;
    }
    final contact = mergedContact;
    final roomId = event.roomId;
    if (contact == null || roomId == null) return null;
    final target = sendRouter.fallbackRoomFor(
      failedRoomId: roomId,
      content: event.content,
      enabled: contact.entry.fallback,
    );
    return target == null ? null : contact.roomById(target);
  }

  /// The name of the network [fallbackRoomFor] offers for [event].
  String? fallbackNetworkName(Event event) {
    final target = fallbackRoomFor(event);
    if (target == null) return null;
    return mergedNetworks(
      MatrixLocals(L10n.of(context)),
    )?.firstWhereOrNull((network) => network.room == target)?.name;
  }

  /// Sends the failed [event] again through the next network and drops the
  /// failed copy. Only on the user's request, never by itself.
  Future<void> resendViaFallback(Event event) async {
    final target = fallbackRoomFor(event);
    if (target == null) return;
    setState(selectedEvents.clear);
    final proceed = await showTrustUserInRoomDialog(context, target);
    if (!mounted || !proceed) return;
    await target.sendEvent(event.content.copy(), type: event.type);
    await event.cancelSend();
  }

  void sendAgainAction() {
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  /// Scrolls the timeline to [eventId]. A thread reply is shown as its
  /// thread's root in the main timeline, unless [openThread] is set, which
  /// opens the thread and scrolls to the reply inside it.
  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
    bool timelineReloaded = false,
    bool openThread = false,
  }) async {
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final threadRootId =
        foundEvent?.relationshipType == RelationshipTypes.thread
        ? foundEvent?.relationshipEventId
        : null;
    if (activeThreadId == null && threadRootId != null) {
      if (!openThread) {
        return scrollToEventId(threadRootId, highlightEvent: highlightEvent);
      }
      enterThread(threadRootId);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scrollToEventId(eventId, highlightEvent: highlightEvent),
      );
      return;
    }

    final eventIndex = foundEvent == null
        ? -1
        : timeline!.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: activeThreadId,
              )
              .indexOf(foundEvent);

    if (eventIndex == -1) {
      if (foundEvent != null || timelineReloaded) return;
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(
          eventId,
          highlightEvent: highlightEvent,
          timelineReloaded: true,
          openThread: openThread,
        );
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    await scrollController.scrollToIndex(
      eventIndex + 1,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
  }

  Future<void> scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(_, Emoji? emoji) {
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final start = selection.baseOffset == -1 ? 0 : selection.baseOffset;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: start + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  /// Escape leaves selection mode wherever focus is in the chat. A dialog or
  /// menu on top keeps the key for itself.
  bool _escapeClearsSelection(KeyEvent evt) {
    if (evt is! KeyDownEvent ||
        evt.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        selectedEvents.isEmpty) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        ModalRoute.of(focusContext) != ModalRoute.of(context)) {
      return false;
    }
    clearSelectedEvents();
    return true;
  }

  /// Makes [event] the only selected message.
  void selectOnly(Event event) => setState(() {
    selectedEvents
      ..clear()
      ..add(event);
  });

  /// Whether a message's right-click menu is open. Its own reaction row
  /// stands in for the picker under the selected message meanwhile.
  bool messageMenuOpen = false;

  void setMessageMenuOpen(bool open) => setState(() => messageMenuOpen = open);

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = this.timeline;
    if (timeline == null) return;

    final client = currentRoomBundle.firstWhere(
      (c) => c?.userID == event.senderId,
      orElse: () => null,
    );
    if (client == null) return;

    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      sendController.text = event
          .getDisplayEvent(timeline)
          .calcLocalizedBody(MatrixLocals(L10n.of(context)), hideReply: true);
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void editSelectedEventAction() {
    _startEditingEvent(selectedEvents.first, clearSelection: true);
  }

  void _editLastSentMessage() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final events = timeline.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );

    final lastOwnMessage = events.firstWhereOrNull(
      (e) =>
          e.type == EventTypes.Message &&
          e.messageType == MessageTypes.Text &&
          e.status.isSent &&
          !e.redacted &&
          currentRoomBundle.any((c) => c?.userID == e.senderId),
    );

    if (lastOwnMessage == null) return;

    _startEditingEvent(lastOwnMessage);
  }

  Future<void> goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.level.compareTo(b.powerLevel.level));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go('/rooms/${result.result!}');

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  void onSelectMessage(Event event) {
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(() => selectedEvents.remove(event));
      } else {
        setState(() => selectedEvents.add(event));
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    // first fetch the last index the event was at
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    // we need to +1 as 0 is the typing thing at the bottom
    return index + 1;
  }

  void onInputBarSubmitted(String _) {
    send();
    FocusScope.of(context).requestFocus(inputFocus);
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: composerRoom),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  Future<void> unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (!mounted) return;
    if (response == OkCancelResult.ok) {
      // The pinned bar lists the pins of the room shown.
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    // A pin is state of the room the message is in.
    final room = roomForEvent(selectedEvents.first, SendAction.pin);
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  /// Height of the composer overlay, which the timeline pads itself by.
  ///
  /// The composer changes height on every frame while the emoji picker,
  /// attachment panel or reply preview animates, so only the timeline's
  /// padding listens to this; the rest of the chat does not rebuild.
  final ValueNotifier<double?> inputBarHeight = ValueNotifier(null);

  void updateInputBarHeight() {
    RenderBox? renderBox;
    if (inputBarKey.currentContext?.findRenderObject() != null) {
      renderBox = inputBarKey.currentContext!.findRenderObject() as RenderBox;
    }

    inputBarHeight.value = renderBox?.size.height ?? 72.0;
  }

  Locale? _suggestionEmojisLocale;
  List<Emoji> _suggestionEmojis = const [];

  /// All emojis of [locale] for the composer's suggestions. The list has
  /// thousands of entries, so it is built once per locale rather than on
  /// every rebuild of the composer.
  List<Emoji> suggestionEmojisFor(Locale locale) {
    if (locale != _suggestionEmojisLocale) {
      _suggestionEmojisLocale = locale;
      _suggestionEmojis = getDefaultEmojiLocale(
        locale,
      ).fold(<Emoji>[], (emojis, category) => emojis..addAll(category.emoji));
    }
    return _suggestionEmojis;
  }

  Stream<bool>? _roomStateUpdates;
  Client? _roomStateUpdatesClient;
  String? _roomStateUpdatesRoomId;

  /// Rate limited state updates for this room, rebuilt only when the
  /// sending client or the room (a merged contact's target) changes. A
  /// stream created in [ChatView.build] would be resubscribed on every
  /// rebuild of the chat.
  Stream<bool> get roomStateUpdates {
    final client = room.client;
    final roomId = room.id;
    if (_roomStateUpdates == null ||
        _roomStateUpdatesClient != client ||
        _roomStateUpdatesRoomId != roomId) {
      _roomStateUpdatesClient = client;
      _roomStateUpdatesRoomId = roomId;
      _roomStateUpdates = client.onRoomState.stream
          .where((update) => update.roomId == roomId)
          .rateLimit(const Duration(seconds: 1));
    }
    return _roomStateUpdates!;
  }

  void onInputBarChanged(String text) {
    inputTextIsEmpty.value = text.isEmpty;

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString(_draftKey, text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingCoolDown = null;
        currentlyTyping = false;
        _typingRoom?.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      final target = composerRoom;
      if (currentlyTyping && _typingRoom != target) {
        // The target changed while typing: stop in the old room first.
        _typingRoom?.setTyping(false);
        currentlyTyping = false;
      }
      if (!currentlyTyping) {
        currentlyTyping = true;
        _typingRoom = target;
        target.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  /// Whether the composer's text was empty when it last changed.
  ///
  /// Only the attachment button and the send button look different with
  /// text in the composer, so they listen to this. Typing the first
  /// character or deleting the last one then rebuilds those two instead of
  /// the whole chat.
  final ValueNotifier<bool> inputTextIsEmpty = ValueNotifier(true);

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  void startOrJoinVideoCall() {
    Matrix.of(context).activeCallRoomId.value = room.id;
  }

  bool supportLiveKitCalls = false;

  Future<void> _cancelEditWithConfirmation() async {
    final originalText = editEvent!
        .getDisplayEvent(timeline!)
        .calcLocalizedBody(MatrixLocals(L10n.of(context)), hideReply: true);

    if (sendController.text != originalText) {
      final result = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).discardEdits,
        okLabel: L10n.of(context).ok,
        cancelLabel: L10n.of(context).cancel,
      );
      if (result == OkCancelResult.cancel) return;
    }

    cancelReplyEventAction();
  }

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  Future<void> toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      actions: kIsWeb
          ? {}
          : <Type, Action<Intent>>{
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (PasteTextIntent intent) =>
                    _handleClipboardImagePaste(),
              ),
            },
      child: Row(
        children: [
          Expanded(child: ChatView(this)),
          ValueListenableBuilder(
            valueListenable: _displayChatDetailsColumn,
            builder: (context, displayChatDetailsColumn, _) =>
                !FluffyThemes.isThreeColumnMode(context) ||
                    room.membership != Membership.join ||
                    !displayChatDetailsColumn
                ? const SizedBox(height: double.infinity, width: 0)
                : Container(
                    width: FluffyThemes.columnWidth,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 1, color: theme.dividerColor),
                      ),
                    ),
                    child: ChatDetails(
                      roomId: roomId,
                      embeddedCloseButton: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: toggleDisplayChatDetailsColumn,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  location,
}
