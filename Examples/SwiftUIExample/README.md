# SwiftUIExample

Native Apple host example for embedding SwiftTUI scenes in a SwiftUI app.

The Xcode project owns the native app shell. `TerminalApp/` is a local Swift
package that defines reusable SwiftTUI scenes, including the component gallery
views, and the SwiftUI app embeds those scenes with `SwiftUIHostAppView`.

## Demonstrates

- `SwiftUIHost` as the native Apple embedding product.
- Reusing SwiftTUI scenes from a separate Swift package.
- Hosting the same `GalleryDemoViews` surface in a native SwiftUI lifecycle.
- Multi-scene authoring through a component-gallery scene and a details scene.

## Run

Open the Xcode project and run the app scheme:

```bash
open Examples/SwiftUIExample/SwiftUIExample.xcodeproj
```

The reusable scene package can be built without opening Xcode:

```bash
swiftly run swift build --package-path Examples/SwiftUIExample/TerminalApp
```

This example currently has no test target. The shared gallery views are tested
by `Examples/gallery`, and the host product is tested under `Platforms/SwiftUI`.
