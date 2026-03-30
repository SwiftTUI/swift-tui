# Android Build

This repo can be cross-compiled for Android with Swift 6.3 using the open-source
Swift toolchain managed by Swiftly.

This follows the repo-wide default described in [TOOLCHAINS.md](TOOLCHAINS.md):
use `swiftly` by default for SwiftPM work, even on native Apple platforms.
Xcode should still work for native-only builds, but Android cross-compilation is
entirely on the `swiftly` path.

## Toolchain

The repo pins Swiftly to `6.3.0` via [`.swift-version`](../.swift-version).
Use `swiftly run swift ...` so builds use the matching open-source toolchain
instead of Xcode's `/usr/bin/swift`.

Verify:

```bash
swiftly run swift --version
```

Expected:

```text
Apple Swift version 6.3 (swift-6.3-RELEASE)
```

## Install the Android SDK

Install the official Swift 6.3 Android SDK bundle:

```bash
swiftly run swift sdk install \
  https://download.swift.org/swift-6.3-release/android-sdk/swift-6.3-RELEASE/swift-6.3-RELEASE_android.artifactbundle.tar.gz \
  --checksum 2f2942c4bcea7965a08665206212c66991dabe23725aeec7c4365fc91acad088
```

## Install and configure the Android NDK

From the installed SDK directory:

```bash
cd ~/Library/org.swift.swiftpm/swift-sdks/swift-6.3-RELEASE_android.artifactbundle/swift-android
curl -fSL -o ndk.zip https://dl.google.com/android/repository/android-ndk-r27d-$(uname -s).zip
unzip -qo ndk.zip
ANDROID_NDK_HOME="$PWD/android-ndk-r27d" ./scripts/setup-android-sdk.sh
```

## Verified targets

These cross-builds were verified locally:

```bash
swiftly run swift build --target Core --swift-sdk aarch64-unknown-linux-android28
swiftly run swift build --target View --swift-sdk aarch64-unknown-linux-android28
swiftly run swift build --target TerminalUICharts --swift-sdk aarch64-unknown-linux-android28
swiftly run swift build --target TerminalUI --swift-sdk aarch64-unknown-linux-android28
```

## Current caveat

`x86_64-unknown-linux-android28` currently fails in the `swift-png` dependency
while importing `_Builtin_intrinsics.intel` for `LZ77/SIMD16 (ext).swift`, so
the Android emulator-oriented `x86_64` path is not yet considered supported.
