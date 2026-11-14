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

### Semantic actions

`swift_tui_android_accessibility_action` accepts one complete UTF-8
RS/newline-framed `accessibility` command, using the same typed values and
percent encoding as the browser. Call it on the host main thread. Its return
value reports command validity and queuing, while `accessibilityActionResponse`
in the next frame reports runtime acceptance or rejection. Commands never pass
through the terminal keyboard parser. Older host libraries lack the symbol;
the Android JNI adapter then returns unsupported.

### Links

The runtime decides what a link activation is, and the Android side performs
the dispatch. When the default `\.openLinkAction` runs — the runtime activated
an enabled `Link` by tap, key or semantic action, or authored code called the
action — the host queues the destination. The Kotlin host drains that queue
through `swift_tui_android_copy_open_link`, one destination per size-then-copy
pair, and opens each one once under its own URI policy. A custom
`OpenLinkAction` runs in Swift and a disabled link registers no action, so
neither reaches the queue.

The action's `true` means the request was queued, not that a destination
opened: the Kotlin host can still refuse the scheme or find no app to handle
it. The action returns `false`, and keeps nothing, for an empty destination,
one longer than 8192 UTF-8 bytes, a seventeenth undelivered request, and
whenever no client has polled the operation. That last case is a host AAR that
predates it, which opens the hyperlink under a tap by itself instead. The
[`swift-tui-android` link reference](https://github.com/SwiftTUI/swift-tui-android/blob/main/docs/LINKS.md)
defines both routes, the allowed schemes and the outcomes.

### Input-method edits

`swift_tui_android_text_input` accepts one complete UTF-8 RS/newline-framed
`textInput` record: the focused text control's action target, its whole text
after an input-method edit, the directed selection and the composing range.
Offsets are UTF-16 code units; `-1:-1` means nothing is composing. Call it on
the host main thread. The return value reports record validity and queuing,
and `accessibilityActionResponse` in the next frame reports whether the
runtime applied the edit. The runtime draws the composing range underlined and
commits it when the control loses keyboard focus or is edited any other way.
A host that never calls the operation keeps today's byte input, and a secure
field always does. Older host libraries lack the symbol; the Android JNI
adapter then reports the operation as unsupported and stays on byte input.
