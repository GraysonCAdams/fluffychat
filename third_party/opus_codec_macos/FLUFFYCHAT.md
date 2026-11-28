# opus_codec_macos 3.0.5, patched for FluffyChat

A copy of the pub.dev release, used through `dependency_overrides` in the
app's `pubspec.yaml`.

Upstream keeps `opus.xcframework` beside the Swift package and points the
package's binary target at `../opus.xcframework`. Flutter links each plugin's
package directory into `macos/Flutter/ephemeral/Packages/.packages/`, and Swift
Package Manager resolves that relative path from the link, where no framework
exists, so the macOS build stops with "local binary target 'opus' ... does not
contain a binary artifact".

The patch moves `opus.xcframework` into `macos/opus_codec_macos/` and points
`Package.swift` and the podspec's `vendored_frameworks` at it there.
`macos/build_xcframework.sh` still writes the framework beside the package; move
its output after running it. To move to a newer release, copy it over this
one and repeat the move, unless upstream ships the framework inside the
package.

The macOS framework inside the pub.dev archive is also flattened: its
`Versions/Current` links are gone, so `Info.plist` sits at the top level and
Xcode refuses to embed it ("contains Info.plist, expected
Versions/Current/Resources/Info.plist"). The copy here is laid out as a
versioned bundle again (`Versions/A` with `Current`, `opus`, `Headers`,
`Modules` and `Resources` as symbolic links). Keep the links when copying.
