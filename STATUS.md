# Global message search: working status (delete before final commit)

Branch `feat/global-message-search`, worktree `/mnt/c/src/fluffychat-search`.
Flutter wrapper for THIS worktree: `<scratchpad>/bin/wfs` -> `C:\src\wfl-search.bat`
(the shared `wfl` wrapper cds into the main checkout, do not use it here).
`flutter pub get` rewrites the generated plugin registrants (line endings): restore with
`git.exe checkout -- linux macos windows` before committing.

## Decisions
- Hook: one sliver widget in `chat_list_body.dart` (it listens to `controller.searchController`
  itself), nothing in `chat_list.dart`. Indexer start: one line in `lib/widgets/matrix.dart` `_registerSubs`.
  Cipher for the index comes from `databaseCiphers` in the database `builder.dart` (calling
  `getDatabaseCipher()` again is unsafe: it deletes the stored key on a failed read).
- SDK stores decrypted events in `box_events` (k = `roomId|eventId`, v = event JSON); limited syncs
  only drop the fragment list, not the events.
- Local path: separate FTS5 file `<client>.search.sqlite`, row ID = timestamp << 21 | hash so
  "newest first" is FTS5's cheap rowid walk. Exploratory numbers (50k events, SQLCipher): LIKE scan of
  box_events 130-190 ms, 300k: 800-1080 ms; FTS ordered by ts column 65-180 ms on common words;
  FTS ordered by rowid ~1 ms. Raw logs: scratchpad `bench1.keep.log`.

## Done
- engines + tests in `lib/utils/message_search/`, `test/utils/message_search/` (68 pass)
- UI section `lib/pages/chat_list/message_search_results.dart`, settings tile, l10n, hooks (analyze clean)

## In progress
- perturbation checks of each test, widget test, indexer integration test, opt-in benchmark numbers

## Next
- try reaching the homeserver for a real server timing (likely not possible), final report, delete this file
