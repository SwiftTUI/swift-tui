# shellcheck shell=bash disable=SC2034  # sourced: every pin is read by its callers
# Pins for the Android cross-compile gate. Sourced, never executed.
#
# Scripts/check_android_cross_compile.sh (the gate) and
# Scripts/install_android_cross_compile_tools.sh (its provisioning) both read
# this file, and the Repo Gate's archive cache is keyed on its hash, so a pin
# bump is one edit here.
#
# Swift SDK for Android. Swift.org publishes one bundle per toolchain release;
# the id, URL and checksum below belong to exactly `android_pin_swift_version`.
# The gate refuses to run when .swift-version moves without them. The checksum
# is the SHA-256 of the archive, which is also what `swift sdk install
# --checksum` verifies.
android_pin_swift_version="6.4.0"
android_swift_sdk_id="swift-6.4.0-RELEASE_android"
android_swift_sdk_url="https://download.swift.org/swift-6.4.0-release/android-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_android.artifactbundle.tar.gz"
android_swift_sdk_sha256="21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43"

# Android NDK. The Swift SDK bundle carries no NDK: its ndk-sysroot is linked
# to a separately installed one by the bundle's own setup-android-sdk.sh. The
# version matches the NDK the Android host ships against (the `sh.swifttui.android`
# Gradle plugin and host AAR in SwiftTUI/swift-tui-android); keep the two in
# step. Google publishes only a SHA-1 for NDK archives (repository2-3.xml lists
# 5107f898313790e449e87eee2183d9a20602dee9 for this file); the SHA-256 below
# was computed from the archive that matched it.
android_ndk_pinned_version="30.0.16248370"
android_ndk_linux_url="https://dl.google.com/android/repository/android-ndk-r30-linux.zip"
android_ndk_linux_sha256="753611f410d002cfcd3f3dc2ef49aad532089d3180b436c060a90bf0fcb64df2"

# What the gate compiles, as `<triple>:<build engine>` steps.
#   * aarch64, default engine: the required contract. arm64-v8a is the
#     packaged ABI, and `default` is what `swift build` selects on the pinned
#     toolchain.
#   * aarch64, native engine: how the `sh.swifttui.android` Gradle plugin
#     builds, and the only step that reads the Swift SDK's materialized
#     ndk-sysroot.
#   * x86_64, default engine: keeps the documented "the Swift host
#     cross-compiles for arm64 and x86_64" claim true.
android_host_target="SwiftTUIAndroidHost"
android_default_steps="aarch64-unknown-linux-android28:default aarch64-unknown-linux-android28:native x86_64-unknown-linux-android28:default"
