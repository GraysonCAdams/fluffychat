# Merged contacts: working status

Temporary file for resuming this branch; removed in the final commit.

- Branch: feat/merged-contacts (worktree /mnt/c/src/fluffychat-merged), base design/chat-list-refresh
- Spec: docs/merged-contacts.md
- Flutter wrapper for this worktree: scratchpad/bin/wflm (runs C:\src\wfl-merged.bat, which cd's here)

## Phase
2 (send-via chip and routing): next

## Done
- phase 1 committed: model/store/merged_contact + tests, chat list collapse (MergedChatList), tile/pins/unread chip, long press menu, merge picker, manage sheet, app bar network switcher
- helper wrote phone_number.dart, contact_identifiers.dart, suggester.dart + tests (uncommitted until phase 4; 78 tests pass)

## Next
- phase 2: SendRouter (pure, tested for every action), send-via chip in composer, route every send call site through it

## Notes
- flutter commands regenerate linux/macos/windows plugin registrants: never stage them
- analyze: 10 pre-existing issues on the base branch (chat_list_body unused vars, chat_list_header, chat_list_view dead code, inline_video_controls_test import); none from this branch

## Decisions
- Store reachable through MergedContactsStore.forClient (Expando) so the push handler can use it without the widget tree
- Stale rooms are dropped from the in-memory view only; stored data keeps them (unmerging loses nothing)
- Removed contacts leave a tombstone (`removed: true`, pruned after 30 days) so per-contact last-write-wins can tell a removal from a contact another device has not seen
