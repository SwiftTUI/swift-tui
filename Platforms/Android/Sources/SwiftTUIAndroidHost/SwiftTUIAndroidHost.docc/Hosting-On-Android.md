# Hosting on Android

Put a SwiftTUI scene inside a native Android app with the Gradle plugin and
Compose host from `swift-tui-android`.

## Overview

The Android integration has two halves. This product —
``AndroidHostSceneHost`` and its C entry points — is the Swift half: it
retains the scene, runs the runtime, and serializes committed frames across a
JNI/C ABI. The Kotlin half — the Compose `SwiftTUIHostView`, the JNI shim,
the packaged AAR, and the Gradle plugin — ships from
[`swift-tui-android`](https://github.com/SwiftTUI/swift-tui-android), whose
README is the integration reference for the Gradle and Kotlin side, including
the current SDK, NDK, and plugin version requirements.

An integration touches four places:

1. **The Gradle plugin.** Apply the SwiftTUI Android plugin and configure its
   `swiftTuiAndroidHost { }` extension in the app module. The plugin
   cross-compiles the Swift package during the Android build and packs the
   native library into the app.
2. **A SwiftPM package for the scene.** The app's SwiftTUI content lives in an
   ordinary Swift package that exposes the scene as a dynamic library the
   plugin can build for Android.
3. **A `@_cdecl` entry point.** One exported Swift function hands the app
   declaration to the host so the JNI bridge can start it.
4. **The Compose mount.** In the activity, `SwiftTUIHostView` renders the
   hosted scene — styled cells, images, and a semantics overlay — and routes
   touch, key, and clipboard traffic back to the Swift runtime.

Android is an arm64 preview tier. The
[`AndroidExample`](https://github.com/SwiftTUI/swift-tui-counter-demo/tree/main/AndroidExample)
app in the counter demo is the maintained end-to-end template: it contains the
four integration files above and the toolchain setup steps.

For where the Android presentation sits in the host matrix — what is bridged,
what is preview-only, and how it compares to the SwiftUI and browser hosts —
see
[Hosts and Platforms](https://swifttui.sh/docs/documentation/swifttuiruntime/hosts-and-platforms).
