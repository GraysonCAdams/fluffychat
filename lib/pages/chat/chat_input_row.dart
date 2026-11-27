// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/pages/chat/recording_input_row.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'composer_attachments.dart';
import 'input_bar.dart';
import 'reply_display.dart';

class ChatInputRow extends StatelessWidget {
  final ChatController controller;

  static const double height = 56.0;

  /// Recording state shared with a [ChatSendButton] outside this row. When
  /// null the row keeps its own.
  final RecordingViewModelState? recording;

  /// Whether the mic and send button sits at the end of this row. The
  /// composer turns it off to draw the button outside its pill.
  final bool showSendButton;

  const ChatInputRow(
    this.controller, {
    this.recording,
    this.showSendButton = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    // In a merged contact's chat the composer names the network the next
    // message goes out on.
    final networks = controller.mergedNetworks(MatrixLocals(L10n.of(context)));
    final target = controller.composerTarget;
    final targetRoom = controller.composerRoom;
    MergedNetwork? targetNetwork;
    if (networks != null) {
      for (final network in networks) {
        if (network.room.id == target.roomId) targetNetwork = network;
      }
    }
    // The hint is the name of the network the message goes out on: the
    // picked one in a merged contact's chat, otherwise the bridge space the
    // chat belongs to. A chat outside any space keeps the generic hint.
    final locals = MatrixLocals(L10n.of(context));
    final hintText =
        targetNetwork?.name ??
        (networks == null
            ? spacesByChild(
                targetRoom.client,
              )[targetRoom.id]?.getLocalizedDisplayname(locals)
            : null) ??
        (targetRoom.encrypted
            ? L10n.of(context).encryptedMessage
            : L10n.of(context).unencryptedMessage);

    Widget buildRow(
      BuildContext context,
      RecordingViewModelState recordingViewModel,
    ) {
      {
        if (recordingViewModel.isRecording) {
          final (sendColor, onSendColor) = controller.sendButtonColors(context);
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
            sendColor: sendColor,
            onSendColor: onSendColor,
          );
        }
        return Row(
          crossAxisAlignment: .end,
          mainAxisAlignment: .spaceBetween,
          children: controller.selectMode
              ? <Widget>[
                  if (controller.selectedEvents.every(
                    (event) => event.status == EventStatus.error,
                  ))
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: controller.deleteErrorEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.delete_forever_outlined),
                            Text(L10n.of(context).delete),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.forwardEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.keyboard_arrow_left_outlined),
                            Text(L10n.of(context).forward),
                          ],
                        ),
                      ),
                    ),
                  controller.selectedEvents.length == 1
                      ? controller.selectedEvents.first
                                .getDisplayEvent(controller.timeline!)
                                .status
                                .isSent
                            ? SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.replyAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).reply),
                                      const Icon(Icons.keyboard_arrow_right),
                                    ],
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (controller.fallbackNetworkName(
                                        controller.selectedEvents.first,
                                      )
                                      case final network?)
                                    SizedBox(
                                      height: height,
                                      child: TextButton(
                                        style: selectedTextButtonStyle,
                                        onPressed: () =>
                                            controller.resendViaFallback(
                                              controller.selectedEvents.first,
                                            ),
                                        child: Text(
                                          L10n.of(
                                            context,
                                          ).sendViaInstead(network),
                                        ),
                                      ),
                                    ),
                                  SizedBox(
                                    height: height,
                                    child: TextButton(
                                      style: selectedTextButtonStyle,
                                      onPressed: controller.sendAgainAction,
                                      child: Row(
                                        children: <Widget>[
                                          Text(L10n.of(context).tryToSendAgain),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.send_outlined,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                      : const SizedBox.shrink(),
                ]
              : <Widget>[
                  const SizedBox(width: 2),
                  // The attach button hides once there is text, which the
                  // chat does not rebuild for (see
                  // ChatController.inputTextIsEmpty).
                  ValueListenableBuilder(
                    valueListenable: controller.inputTextIsEmpty,
                    builder: (context, _, _) => ComposerLeadingButtons(
                      textMessageOnly:
                          controller.sendController.text.isNotEmpty ||
                          controller.replyEvent != null ||
                          controller.editEvent != null,
                      attachmentPanelOpen: controller.showAttachmentPanel,
                      onAttach: controller.toggleAttachmentPanel,
                      // Android keyboards carry their own emoji picker.
                      showEmojiButton: !PlatformInfos.isAndroid,
                      emojiPickerOpen: controller.showEmojiPicker,
                      onEmoji: controller.emojiPickerAction,
                    ),
                  ),
                  if (Matrix.of(context).isMultiAccount &&
                      Matrix.of(context).hasComplexBundles &&
                      Matrix.of(context).currentBundle!.length > 1)
                    Container(
                      height: height,
                      width: 48,
                      alignment: Alignment.center,
                      child: _ChatAccountPicker(controller),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: InputBar(
                        room: controller.room,
                        minLines: 1,
                        maxLines: 8,
                        autofocus: !PlatformInfos.isMobile,
                        keyboardType: TextInputType.multiline,
                        textInputAction:
                            AppSettings.sendOnEnter.value == true &&
                                PlatformInfos.isMobile
                            ? TextInputAction.send
                            : null,
                        onSubmitted: controller.onInputBarSubmitted,
                        onSubmitImage: controller.sendImageFromClipBoard,
                        onInsertFile: (file) =>
                            controller.addPendingAttachments([file]),
                        focusNode: controller.inputFocus,
                        controller: controller.sendController,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.only(
                            left: 2.0,
                            right: 6.0,
                            bottom: 6.0,
                            top: 3.0,
                          ),
                          counter: const SizedBox.shrink(),
                          hintText: hintText,
                          hintMaxLines: 1,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          filled: false,
                        ),
                        onChanged: controller.onInputBarChanged,
                        undoController: controller.undoController,
                        suggestionEmojis: controller.suggestionEmojisFor(
                          AppSettings.emojiSuggestionLocale.value.isNotEmpty
                              ? Locale(AppSettings.emojiSuggestionLocale.value)
                              : Localizations.localeOf(context),
                        ),
                      ),
                    ),
                  ),
                  if (showSendButton)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChatSendButton(
                        controller,
                        recordingViewModel,
                        compact: true,
                      ),
                    ),
                ],
        );
      }
    }

    final recording = this.recording;
    return recording != null
        ? buildRow(context, recording)
        : RecordingViewModel(builder: buildRow);
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(
      context,
    ).currentBundle!.firstWhere((cl) => cl!.userID == mxid, orElse: () => null);
    if (client == null) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<Profile>(
        future: controller.sendingClient.fetchOwnProfile(),
        builder: (context, snapshot) => PopupMenuButton<String>(
          useRootNavigator: true,
          onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
          itemBuilder: (BuildContext context) => clients
              .map(
                (client) => PopupMenuItem(
                  value: client!.userID,
                  child: FutureBuilder<Profile>(
                    future: client.fetchOwnProfile(),
                    builder: (context, snapshot) => ListTile(
                      leading: Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name:
                            snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 20,
                      ),
                      title: Text(snapshot.data?.displayName ?? client.userID!),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
              )
              .toList(),
          child: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name:
                snapshot.data?.displayName ??
                Matrix.of(context).client.userID!.localpart,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// The mic and send button, a circle beside the composer's pill as in
/// Google Messages. Long-pressing the mic records a voice message through
/// [recordingViewModel], which the input row shares to show the recorder.
///
/// The mic turns into the send button once there is text, which the chat
/// does not rebuild for, so this listens to
/// [ChatController.inputTextIsEmpty] itself.
class ChatSendButton extends StatelessWidget {
  final ChatController controller;
  final RecordingViewModelState recordingViewModel;

  /// A smaller button for inside the composer's pill.
  final bool compact;

  const ChatSendButton(
    this.controller,
    this.recordingViewModel, {
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller.inputTextIsEmpty,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final (background, foreground) = controller.sendButtonColors(context);
    final size = compact ? 40.0 : ChatInputRow.height;
    return Container(
      height: ChatInputRow.height,
      width: compact ? 48 : ChatInputRow.height,
      alignment: Alignment.center,
      child:
          PlatformInfos.platformCanRecord &&
              AppSettings.voiceMessages.value &&
              !controller.sendController.text.isNotEmpty &&
              controller.pendingAttachments.isEmpty &&
              controller.editEvent == null
          ? HoverBuilder(
              builder: (context, hovered) => IconButton(
                tooltip: L10n.of(context).voiceMessage,
                onPressed: hovered
                    ? () => recordingViewModel.startRecording(controller.room)
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          margin: EdgeInsets.only(
                            bottom: ChatInputRow.height + 16,
                            left: 16,
                            right: 16,
                            top: 16,
                          ),
                          showCloseIcon: true,
                          content: Text(
                            L10n.of(context).longPressToRecordVoiceMessage,
                          ),
                        ),
                      ),
                onLongPress: () =>
                    recordingViewModel.startRecording(controller.room),
                style: IconButton.styleFrom(
                  fixedSize: Size.square(size),
                  minimumSize: Size.square(size),
                  padding: EdgeInsets.zero,
                  backgroundColor: background,
                  foregroundColor: foreground,
                ),
                icon: Icon(hovered ? Icons.mic : Icons.mic_none_outlined),
              ),
            )
          : GestureDetector(
              // Right click offers scheduling. So does a long press, except
              // in an iMessage chat, where it offers the message effects.
              onSecondaryTap: controller.openSendOptions,
              child: IconButton(
                key: Key('send_button'),
                tooltip: L10n.of(context).send,
                onPressed: controller.send,
                onLongPress: () =>
                    controller.onSendLongPress(background, foreground),
                style: IconButton.styleFrom(
                  fixedSize: Size.square(size),
                  minimumSize: Size.square(size),
                  padding: EdgeInsets.zero,
                  backgroundColor: background,
                  foregroundColor: foreground,
                ),
                icon: const Icon(Icons.send_outlined),
              ),
            ),
    );
  }
}

/// The message composer: a pill holding the reply preview, staged
/// attachments and the input row, with the send button at its end.
class ChatComposer extends StatelessWidget {
  final ChatController controller;

  const ChatComposer(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RecordingViewModel(
      builder: (context, recording) {
        final showSendButton =
            !recording.isRecording &&
            !controller.selectMode &&
            controller.room.otherPartyCanReceiveMessages;
        return Row(
          crossAxisAlignment: .end,
          children: [
            Expanded(
              child: Material(
                clipBehavior: Clip.hardEdge,
                color: controller.selectedEvents.isNotEmpty
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(ChatInputRow.height / 2),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    ReplyDisplay(controller),
                    ComposerAttachmentStrip(
                      files: controller.pendingAttachments,
                      onRemove: controller.removePendingAttachment,
                    ),
                    ChatInputRow(
                      controller,
                      recording: recording,
                      showSendButton: showSendButton,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The attach and emoji buttons at the start of the composer, 40dp wide
/// each and side by side, so their icons sit 16dp apart. Once the message
/// has text ([textMessageOnly]) the attach button folds away, leaving its
/// slot as the text's inset from the composer's rounded edge.
class ComposerLeadingButtons extends StatelessWidget {
  final bool textMessageOnly;
  final bool attachmentPanelOpen;
  final void Function() onAttach;
  final bool showEmojiButton;
  final bool emojiPickerOpen;
  final void Function() onEmoji;

  /// Each button's width and touch target.
  static const double buttonSize = 40;

  const ComposerLeadingButtons({
    required this.textMessageOnly,
    required this.attachmentPanelOpen,
    required this.onAttach,
    required this.showEmojiButton,
    required this.emojiPickerOpen,
    required this.onEmoji,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final style = IconButton.styleFrom(
      fixedSize: const Size.square(buttonSize),
      minimumSize: const Size.square(buttonSize),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          width: textMessageOnly ? 16 : buttonSize,
          height: ChatInputRow.height,
          alignment: Alignment.center,
          decoration: const BoxDecoration(),
          clipBehavior: Clip.hardEdge,
          child: textMessageOnly
              ? null
              : IconButton(
                  key: const ValueKey('composer-attach'),
                  tooltip: l10n.addAttachment,
                  style: style,
                  icon: Icon(
                    attachmentPanelOpen
                        ? Icons.close
                        : Icons.add_circle_outline,
                  ),
                  color: theme.colorScheme.onPrimaryContainer,
                  onPressed: onAttach,
                ),
        ),
        if (showEmojiButton)
          SizedBox(
            height: ChatInputRow.height,
            width: buttonSize,
            child: Center(
              child: IconButton(
                key: const ValueKey('composer-emoji'),
                tooltip: l10n.emojis,
                style: style,
                color: theme.colorScheme.onPrimaryContainer,
                icon: Icon(
                  emojiPickerOpen
                      ? Icons.keyboard
                      : Icons.add_reaction_outlined,
                  key: ValueKey(emojiPickerOpen),
                ),
                onPressed: onEmoji,
              ),
            ),
          ),
      ],
    );
  }
}
