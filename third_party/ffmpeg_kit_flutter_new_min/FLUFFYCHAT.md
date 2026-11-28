# ffmpeg_kit_flutter_new_min 2.1.0, patched for FluffyChat

A copy of the pub.dev release without its `ios/`, `macos/`, `example/` and
`scripts/` directories, used through `dependency_overrides` in the app's
`pubspec.yaml`. The app reaches this plugin only through `whisper_ggml`, which
converts audio with it before transcribing a voice message.

The patch removes the `ios` and `macos` entries from `flutter.plugin.platforms`
in `pubspec.yaml`, so the plugin is Android only. Its iOS frameworks carry an
arm64 slice built for devices and no arm64 simulator slice, which stops every
simulator build on an Apple silicon Mac at the link step ("Building for
'iOS-simulator', but linking in dylib ... built for 'iOS'"), and they add
about 45 MB to the app. Voice transcription on iOS and macOS does not go
through `whisper_ggml`, so nothing calls the plugin there; a call would throw
`MissingPluginException`.

To move to a newer release, copy its `android/`, `lib/` and `pubspec.yaml`
over this one and remove the two platform entries again.
