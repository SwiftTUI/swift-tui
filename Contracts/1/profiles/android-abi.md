# Android native ABI 1

The normative declarations are in `../include/swift_tui_android.h`. The AAR's
JNI bindings use Kotlin `Long` for the signed 64-bit opaque handle, `Int` for
signed 32-bit counts/status, and `Double` for IEEE 754 binary64 cell metrics.
Supported Android targets are little-endian. Handles are never pointers and
must not be synthesized or reused after destruction. Zero is factory failure.

`get_abi_info` is callable before executor installation, without a handle. Its
32-byte prefix consists of eight little-endian unsigned 32-bit integers:
struct byte size, ABI major, ABI minor, handle bits, count bits, scalar bits,
optional-operation bits, reserved zero. A null buffer or capacity ≤0 is a size
query. A smaller positive buffer receives exactly that many prefix bytes; a
larger buffer receives only 32 bytes. The return value is always the producer's
complete size. Future ABI-1 descriptors append fields; older callers ignore
the tail. A short producer prefix is incompatible with this reader. Minor
revisions add optional operations only: minor 1 adds copy open link and take
clipboard. Callers detect an operation by its bit, never by the minor number,
and ignore bits they do not know.

The loader resolves the required and optional table once before publishing JNI
methods. Required: install executor, application factory, start, tick, stop,
destroy, resize, send input and copy latest frame. The application supplies
`create_host`; the framework supplies the other exports. An ABI query identifies
major/minor and argument widths separately from package versions and wire
capabilities. The loader rejects incompatible majors and widths before any
executor installation or factory call. A claimed optional bit without its
symbol is an incompatible library. An absent optional bit means unsupported,
even if the library exports a symbol of that name.

The bounded legacy policy admits the pre-query 0.20.1 symbol contract only when
all required symbols exist. Optional symbols are detected once. This is symbol
compatibility, not a claim to identify arbitrary historical package versions.
An unknown library with conflicting C signatures is outside that legacy contract.

| Operation | Ownership, result and failure |
| --- | --- |
| install executor | Call on the Android main looper before all Swift main-actor work. Idempotent; captures the owning thread. |
| create host | Application factory returns a registered positive handle; zero fails creation. No partial host may be started. |
| start / stop | Owning main thread. Start schedules the scene; stop cancels it. Repeated calls are safe. Invalid handles do nothing. |
| tick | Owning main thread; drives the executor and scene. Returns the number of main-executor jobs drained (clamped to Int32); zero also covers an invalid handle. This is not a frame-availability signal. |
| destroy | Owning main thread. Removes the handle, stops the scene and releases its retained candidate/input state. Further handle calls have invalid-handle behavior. |
| resize | Owning main thread. Columns/rows below one clamp to one. Nonfinite, negative or over-limit cell metrics and over-limit grids are rejected without partial geometry changes; zero cell pitch clamps to one. |
| send input | Owning main thread. Borrows bytes only for the call, copying admitted input into the host. Null, nonpositive or over-budget counts are ignored. |
| copy latest frame | Borrows output memory only for the call. Returns required UTF-8 byte count, with no terminating NUL. Null/undersized buffers consume nothing and write nothing; successful copies commit exactly the prepared candidate. Zero means no deliverable frame/invalid handle. |
| copy clipboard | Optional; independent from frame delivery. Same query/copy convention; successful copy drains the current clipboard text once. Embedded NUL is ordinary UTF-8 data. Zero means nothing pending or an invalid handle, so this operation cannot report an empty write and never drains one. |
| take clipboard | Optional, minor 1; drains the same clipboard text as copy clipboard. Returns -1 when nothing is pending or the handle is invalid, otherwise the required UTF-8 byte count, where 0 is a pending empty write. Null/undersized buffers consume nothing; a non-null buffer with enough capacity copies and drains, and an empty text is drained at any capacity. The first call on a handle declares that the caller delivers empty text. |
| declare capabilities | Optional; owning main thread, before start. Borrowed UTF-8 JSON. Returns 1 only for accepted declaration, otherwise 0. Missing operation preserves legacy full-frame defaults. |
| request resync | Optional; borrowed UTF-8 JSON. Returns 1 for admitted repair, otherwise 0. Invalidates an older prepared frame. Missing operation leaves recovery pending until an incidental full frame. |
| accessibility action | Optional; owning main thread. Borrowed complete UTF-8 action record. 1 means queued ingress, not runtime acceptance; the correlated response carries the eventual result. 0 means rejected/unsupported ingress. |
| diagnostics | Optional, packed executor counters; diagnostic only, never a compatibility decision. |
| copy open link | Optional, minor 1; independent from frame delivery. Same query/copy convention as the clipboard, over a first-in, first-out queue: a successful copy removes exactly the oldest destination, so the caller repeats the query/copy pair until zero. The payload is the destination's UTF-8 bytes as authored; the caller owns URI validation and dispatch. The first call, a size query included, registers the caller as the link dispatcher. Zero means nothing pending or an invalid handle. |

A destination enters the open-link queue only when the runtime's default
open-link action runs: an activated enabled link, or authored code that calls
the default action. A custom action and a disabled link never enqueue. Until a
caller has registered through `copy open link`, the default action reports
`false` and retains nothing, which is also the complete behavior of a library
that lacks the operation. After registration, the action's `true` reports an
accepted request, not an opened destination. The queue holds at most 16
destinations of at most 8192 bytes each; a request beyond either bound is
refused with `false`. Starting a new scene run discards undelivered requests.

An application's empty clipboard write means "clear the clipboard". The host
admits it, replacing any undrained text, only for a caller that has used take
clipboard on that handle. For every other caller the write is refused and the
application's write action reports failure, as in minor 0: the copy clipboard
result cannot distinguish an empty text from no text, so such a caller would
never deliver it. A caller that takes should make its first call before start.

Copy and repair operations synchronize their host-owned state. Callers still
serialize lifecycle and destruction with all handle use; a handle lookup is not
a lifetime pin promised to foreign concurrent callers. Wrong-thread lifecycle
calls trap with the named accessor, including optimized builds. Retry a failed
size/copy with the reported capacity. Do not retry a successful action merely
because its response has not yet arrived.

Startup failures use stable prefixes: `android.abi.loadLibrary`,
`android.abi.missingRequired`, `android.abi.shortInfo`,
`android.abi.incompatibleMajor`, `android.abi.argumentWidth`, and
`android.abi.missingAdvertised`. JNI reports an `UnsatisfiedLinkError` with the
prefix and missing requirement; it never silently starts a partial host.
