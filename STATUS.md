# fix/send-media status

Branch from `fork/feat/integration2`. Worktree `C:\src\fluffychat-sendmedia`.

## Done

- Outgoing photo or video draws from its own bytes at full sharpness from
  the moment it is sent, at its real aspect: `sendAttachments` reads the
  image size from its header (`fillImageSize`) and primes the MxcImage
  cache under the transaction ID (`primeLocalMediaPreview`); a video's
  poster frame is primed the same way and `_VideoPoster` uses it.
- `MediaSendingIndicator`: white indeterminate ring on a dark disc,
  bottom-right of the media, after 300 ms, as Google Messages does. No
  scrim. Media status line shows the mark only, no "Sending" text.
- `com.beeper.dont_render_edited` edits no longer show "(edited)"
  (`lib/utils/edited_mark.dart`, test `test/utils/edited_mark_test.dart`).
- A shown MxcImage keeps the bytes it drew when `MxcImage.clearCache`
  empties the cache under it (a chat page disposed while a new one shows,
  as on rotation); it used to fall back to its placeholder for good. Seen
  on the Pixel as a sent photo stuck on its BlurHash; test
  `test/widgets/mxc_image_cache_test.dart` fails without the fix.
- Review renders: `test/screenshots/send_media_states_test.dart` writes
  PNGs to `build/send_media_states`.

## Open

- Google's ring is determinate and holds a cancel X. The SDK's
  `Room.sendFileEvent` reports no upload progress and cannot abort an
  upload, so Seam's ring is indeterminate and has no X.
- Slow-mo share sheet: not reproduced. Seam is listed in the Photos
  chooser for the 120 fps clip and the share stages it. Waiting on which
  sheet Grayson meant.
- Pending received media tile (gmessages "Waiting for attachment"):
  mockup only, waiting on Grayson's approval.
