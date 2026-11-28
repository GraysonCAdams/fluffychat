#!/usr/bin/env bash
# Builds SeamNseCrypto.xcframework, the static library the Notification
# Service Extension links for Megolm decryption.
#
# Slices: aarch64-apple-ios (device) and aarch64-apple-ios-sim (simulator).
# iOS 26 simulators run on Apple silicon only, so there is no x86_64 slice.
#
# Usage: ios/seam_nse_crypto/build_xcframework.sh
# Needs rustup with the aarch64-apple-ios and aarch64-apple-ios-sim targets,
# and Xcode's command line tools.
set -euo pipefail

cd "$(dirname "$0")"
crate_dir="$PWD"
out="$crate_dir/SeamNseCrypto.xcframework"
targets=(aarch64-apple-ios aarch64-apple-ios-sim)

# The extension's deployment target. rustc reads this when it links and
# stamps the minimum OS version into every object file.
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export CARGO_TARGET_DIR="$crate_dir/target"

# Xcode build phases export SDK and architecture variables meant for clang.
# Cargo picks the SDK per target itself, so clear them to keep the device and
# simulator builds from borrowing each other's settings.
unset SDKROOT PLATFORM_NAME ARCHS

# Build phases also run with a minimal PATH that misses rustup's shims.
export PATH="$HOME/.cargo/bin:$PATH"

for target in "${targets[@]}"; do
    cargo build --release --locked --lib --target "$target"
done

rm -rf "$out"
args=()
for target in "${targets[@]}"; do
    args+=(-library "$CARGO_TARGET_DIR/$target/release/libseam_nse_crypto.a" -headers "$crate_dir/include")
done
xcodebuild -create-xcframework "${args[@]}" -output "$out" >/dev/null

for target in "${targets[@]}"; do
    lib="$CARGO_TARGET_DIR/$target/release/libseam_nse_crypto.a"
    printf '%s: %s bytes\n' "$target" "$(stat -f %z "$lib")"
done
echo "Wrote $out"
