# opus_codec_ios 3.0.5, patched for FluffyChat

A copy of the pub.dev release, used through `dependency_overrides` in the
app's `pubspec.yaml`.

Upstream keeps `opus.xcframework` beside the Swift package and points the
package's binary target at `../opus.xcframework`. Flutter links each plugin's
package directory into `ios/Flutter/ephemeral/Packages/.packages/`, and Swift
Package Manager resolves that relative path from the link, where no framework
exists, so the iOS build stops with "local binary target 'opus' ... does not
contain a binary artifact".

The patch moves `opus.xcframework` into `ios/opus_codec_ios/` and points
`Package.swift` and the podspec's `vendored_frameworks` at it there.
`ios/build_xcframework.sh` still writes the framework beside the package; move
its output after running it. To move to a newer release, copy it over this
one and repeat the move, unless upstream ships the framework inside the
package.
