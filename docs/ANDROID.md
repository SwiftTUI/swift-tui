# Android Build

This repo can be cross-compiled for Android with Swift 6.3.1 using the
open-source Swift toolchain managed by Swiftly. Android cross-compilation is
entirely on the `swiftly` path; see [TOOLCHAINS.md](TOOLCHAINS.md) for the
canonical toolchain rules.

## Install the Android SDK

Install the official Swift 6.3.1 Android SDK bundle:

```bash
swiftly run swift sdk install \
  https://download.swift.org/swift-6.3.1-release/android-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_android.artifactbundle.tar.gz \
  --checksum 8193a4e96538635131a154736c8896fba0e5a1c30e065524f00ed78719bac35a
```

## Install and configure the Android NDK

From the installed SDK directory:

```bash
cd ~/Library/org.swift.swiftpm/swift-sdks/swift-6.3.1-RELEASE_android.artifactbundle/swift-android
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
