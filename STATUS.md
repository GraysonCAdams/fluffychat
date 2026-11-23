# Merged contacts: working status

Temporary file for resuming this branch; removed in the final commit.

- Branch: feat/merged-contacts (worktree /mnt/c/src/fluffychat-merged), base design/chat-list-refresh
- Spec: docs/merged-contacts.md
- Flutter wrapper for this worktree: scratchpad/bin/wflm (runs C:\src\wfl-merged.bat, which cd's here)

## Phase
5 (fallback offer on failed sends): next

## Done
- phase 1 committed: model/store/merged_contact + tests, chat list collapse (MergedChatList), tile/pins/unread chip, long press menu, merge picker, manage sheet, app bar network switcher
- helper wrote phone_number.dart, contact_identifiers.dart, suggester.dart + tests (uncommitted until phase 4; 78 tests pass)

- phase 2 committed: SendRouter (+ tests per action), RoutedEvent extension for message widgets, SendViaChip (+ widget tests), ChatController composerTarget/composerRoom/roomForEvent, all send sites routed

- fix commit: tile opened /rooms/contact before that route existed (opened send_via room until phase 3)
- phase 3 committed: MergedOrder (generic, tested), MergedTimeline implements Timeline (+ tests), /rooms/contact/:id + redirect (single=1 escape), controller merged mode (room = target, one-off pick, per-room read markers, draft per contact), app bar subtitle, per-message network badge

- phase 4 committed: phone/identifier/suggester modules (helper) + MergeSuggestionService (+ tests), banner, settings page + route, AppSettings (suggestions switch, region), notification conversation key per contact (push helper, desktop notifications, cancel on read), active chat for contact route

## Next
- phase 5: fallback offer ("Send via <next network> instead") on failed new messages when contact.fallback; switch in manage sheet; tests; then final cleanup (remove STATUS.md), full analyze + test run, report

## Notes
- flutter commands regenerate linux/macos/windows plugin registrants: never stage them
- analyze: 10 pre-existing issues on the base branch (chat_list_body unused vars, chat_list_header, chat_list_view dead code, inline_video_controls_test import); none from this branch

## Decisions
- Store reachable through MergedContactsStore.forClient (Expando) so the push handler can use it without the widget tree
- Stale rooms are dropped from the in-memory view only; stored data keeps them (unmerging loses nothing)
- Removed contacts leave a tombstone (`removed: true`, pruned after 30 days) so per-contact last-write-wins can tell a removal from a contact another device has not seen
