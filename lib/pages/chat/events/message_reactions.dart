// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:fluffychat/utils/merged_contacts/routed_event.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final reactionMap = <String, _ReactionEntry>{};
    final client = Matrix.of(context).client;

    for (final e in allReactionEvents) {
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactors: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactors!.add(e.senderFromMemoryOrFallback);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      alignment: ownMessage ? WrapAlignment.end : WrapAlignment.start,
      children: [
        ...reactionList.map(
          (r) => _Reaction(
            reactionKey: r.key,
            count: r.count,
            reacted: r.reacted,
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: evt.status.isSent
                        ? evt.redactEvent
                        : evt.cancelSend,
                  );
                }
              } else {
                event
                    .roomFor(SendAction.reaction)
                    .sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async => await _AdaptableReactorsDialog(
              client: client,
              reactionEntry: r,
            ).show(context),
          ),
        ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool? reacted;
  final void Function()? onTap;
  final void Function()? onLongPress;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (reactionKey.startsWith('mxc://')) {
      content = MxcImage(
        uri: Uri.parse(reactionKey),
        width: 20,
        height: 20,
        animated: false,
        isThumbnail: false,
      );
    } else {
      var renderKey = Characters(reactionKey);
      if (renderKey.length > 10) {
        renderKey = renderKey.getRange(0, 9) + Characters('…');
      }
      content = Text(renderKey.toString(), style: TextStyle(fontSize: 14));
    }
    // A pill as tall as [reactionChipHeight], ringed in the page colour so it
    // stands apart from the bubble it overlaps. The user's own reactions fill
    // with the secondary container colour.
    final borderRadius = BorderRadius.circular(reactionChipHeight / 2);
    final foreground = reacted == true
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    return Material(
      color: reacted == true
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: theme.colorScheme.surface, width: 2),
      ),
      child: InkWell(
        onTap: () => onTap != null ? onTap!() : null,
        onLongPress: () => onLongPress != null ? onLongPress!() : null,
        customBorder: RoundedRectangleBorder(borderRadius: borderRadius),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: reactionChipHeight,
            minHeight: reactionChipHeight,
            maxHeight: reactionChipHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              content,
              if (count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Height of one reaction chip.
const double reactionChipHeight = 28;

/// How far a reaction chip reaches up over the bubble's bottom edge.
const double reactionChipOverlap = 8;

/// Lays a message bubble out with its reaction chips hanging off the
/// bubble's bottom corner: the chips overlap the bubble by
/// [reactionChipOverlap] and the rest of their height is added below the
/// bubble, so they never cover the next message.
///
/// With [reactionsAtEnd] the chips line up with the bubble's right edge,
/// otherwise with its left edge. Chips wider than the bubble start at the
/// bubble's edge and run past its other side, and the bubble keeps its own
/// alignment: left for another sender's message, right for the user's own.
/// Without [reactions] the bubble is returned as it is.
class BubbleWithReactions extends StatelessWidget {
  final Widget bubble;
  final Widget? reactions;
  final bool reactionsAtEnd;

  const BubbleWithReactions({
    required this.bubble,
    required this.reactions,
    required this.reactionsAtEnd,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final reactions = this.reactions;
    if (reactions == null) return bubble;
    return _BubbleWithReactionsLayout(
      reactionsAtEnd: reactionsAtEnd,
      children: [bubble, reactions],
    );
  }
}

class _BubbleWithReactionsLayout extends MultiChildRenderObjectWidget {
  final bool reactionsAtEnd;

  const _BubbleWithReactionsLayout({
    required this.reactionsAtEnd,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBubbleWithReactions(reactionsAtEnd);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBubbleWithReactions renderObject,
  ) => renderObject.reactionsAtEnd = reactionsAtEnd;
}

class _BubbleWithReactionsParentData
    extends ContainerBoxParentData<RenderBox> {}

class _RenderBubbleWithReactions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BubbleWithReactionsParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _BubbleWithReactionsParentData
        > {
  _RenderBubbleWithReactions(this._reactionsAtEnd);

  bool _reactionsAtEnd;
  set reactionsAtEnd(bool value) {
    if (value == _reactionsAtEnd) return;
    _reactionsAtEnd = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BubbleWithReactionsParentData) {
      child.parentData = _BubbleWithReactionsParentData();
    }
  }

  @override
  void performLayout() {
    final bubble = firstChild!;
    final reactions = childAfter(bubble)!;
    final loose = constraints.loosen();
    bubble.layout(loose, parentUsesSize: true);
    reactions.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final double width = max(bubble.size.width, reactions.size.width);
    final overlap = min(reactionChipOverlap, bubble.size.height);
    size = constraints.constrain(
      Size(width, bubble.size.height + reactions.size.height - overlap),
    );

    // The bubble keeps the side it would have without reactions: another
    // sender's (chips at the end) on the left, the user's own on the right.
    final bubbleX = _reactionsAtEnd ? 0.0 : size.width - bubble.size.width;
    final reactionsX = _reactionsAtEnd
        ? max(0.0, bubbleX + bubble.size.width - reactions.size.width)
        : min(bubbleX, size.width - reactions.size.width);
    (bubble.parentData! as _BubbleWithReactionsParentData).offset = Offset(
      bubbleX,
      0,
    );
    (reactions.parentData! as _BubbleWithReactionsParentData).offset = Offset(
      reactionsX,
      bubble.size.height - overlap,
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<User>? reactors;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactors,
  });
}

class _AdaptableReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;

  const _AdaptableReactorsDialog({this.client, this.reactionEntry});

  Future<bool?> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => this,
    barrierDismissible: true,
    useRootNavigator: false,
  );

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in reactionEntry!.reactors!)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.displayName,
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(reactor.displayName!),
            ),
        ],
      ),
    );

    final title = Center(child: Text(reactionEntry!.key));

    return AlertDialog(title: title, content: body);
  }
}
