# Compiled Hot Reload

Rebuild a terminal application's Swift view code while preserving compatible
state in the running process.

## Run the driver

`swifttui-dev` supports debug terminal apps on macOS and Linux with Swift 6.3.3
managed by Swiftly. Build the executable from this package, then point it at a
Swift package containing one executable target:

```sh
swiftly run swift build --product swifttui-dev
.build/debug/swifttui-dev --package-path /path/to/app --product MyApp
```

The selected app must use this framework revision's reload API. Supply its root
view through a public C export. Keep the normal `App` and `WindowGroup` entry
point; the driver builds and launches it once before loading replacement roots.

```swift
#if DEBUG && SWIFTTUI_HOT_RELOAD && (os(macOS) || os(Linux))
@_cdecl("swifttui_hot_reload_root")
@MainActor public func reloadRoot() -> UnsafeMutableRawPointer {
  HotReloadExport.retainedRoot { MyRootView() }
}
#endif
```

The driver supplies `SWIFTTUI_HOT_RELOAD` and the scalar compatibility exports.
Return the retained payload directly: the loader takes ownership exactly once.
The factory constructs a fresh root without starting external work. Put tasks
and effects in view lifecycle modifiers because schema discovery evaluates the
candidate before publishing it. Reload replaces the root content of the terminal
session; scene declarations and additional windows are outside this contract.

After SwiftPM builds the initial host, the driver reads its structured compiler
command from `description.json`. It recompiles the executable target's Swift
sources with those settings and a unique ABI module name, then links each image
against the host's framework symbols. Distinct runtime type names prevent
duplicate Swift/Objective-C class registration. Replay compares explicitly
declared logical module aliases in Codable schema names and framework-generated
`AnyView` type components; it does not change application data or authored identity keys.

`--debounce-ms` sets the quiet period (200 ms by default). `--target` selects the
executable target explicitly. Arguments after `--` go to the app. Build or link
failures leave the current generation interactive. While the app owns the
terminal, compiler diagnostics go to the private spool's `diagnostics.log` and
the optional JSON event log. The initial build prints the log location; follow
it from another terminal. An unresolved diagnostic prints on stderr after the
app stops. This keeps compiler text out of the application's raster. A newer
edit discards an in-flight candidate. The driver restarts neither
the app nor its input stream for an accepted reload.

## State and effects

Compatible initialized `@State` and focus values replay through Codable value
snapshots. Scroll offsets and inactive-tab values replay as well. References
decode into new instances; old closures, task handles and application metadata
never become replacement state. Non-Codable, transient, ambiguous or changed
slot schemas reset to authored seeds and produce dropped-slot diagnostics.
Uninitialized state uses the new seed. Exact structural owners win before the
limited unique-wrapper and declaration-rank fallback rules. Entity identity and
sibling position do not become interchangeable. Codable type names must agree;
file-private or nested types whose reflected name changes may reset.

Old lifecycle work retires before new lifecycle work starts. New bodies, actions
and tasks execute the replacement code. Custom Codable methods and root
construction run application code and must be safe to evaluate during discovery.
Task cancellation is requested before replacement tasks start; cancelled tasks
can finish their cleanup asynchronously. Capture values needed after an `await`
before suspending instead of reading a retired owner's state during cleanup.

## Restart boundaries and measurement

Changing package manifests, dependency contents, lockfiles, resources, the set
of source files or the Swift toolchain requires a restart. Only existing Swift
files in the selected executable
target reload; dependency targets keep the executable's single framework and
library copies. The driver detects SwiftPM compiler descriptions and rejects
unsupported layouts. Explicit `@objc(...)` names are process-global and are
rejected for image compilation. Plugins and external generated inputs are outside the supported
single-target workflow; restart after changing them.

Runtime names embedded in custom identity keys can differ between images;
those owners reset under the ordinary
identity rules. Keep stable explicit identities independent of reflected type
names when state continuity is required.

Loaded images remain mapped because Swift runtime metadata can outlive a root.
After 100 image attempts the next edit exits the app and requests a restart;
`--max-reloads` can lower this bound. The private spool is removed on driver
shutdown. Memory usage depends on image size and must be measured for each app.

`--event-log /path/to/events.jsonl` records build failures, discarded candidates,
load failures and committed frames. `observedEditToFrameMilliseconds` starts at
the driver's first observation of the accepted edit; polling can add up to
roughly 50 ms before that observation. `buildToFrameMilliseconds` starts at
compilation. Both end after the app acknowledges a committed frame. These are
measurements, not latency guarantees.

Release builds, WASI, native SwiftUI hosts and Android do not expose the loader
or `HotReloadExport`. Ordinary debug sessions register no reload signal unless
launched by the driver.
