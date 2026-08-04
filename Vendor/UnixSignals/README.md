# UnixSignals (vendored)

A vendored subset of the `UnixSignals` module from the
[Swift Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle)
project, consumed by this package as `SwiftTUIVendorUnixSignals`. It provides
the async signal-handling primitives behind `CrashSignalHandler` and the
runner-installed terminal-restore path.

## Provenance and license

Upstream: `swift-server/swift-service-lifecycle` (The ServiceLifecycle
Project). Licensed under the Apache License 2.0 — see
[LICENSE.txt](LICENSE.txt), [NOTICE.txt](NOTICE.txt), and
[CONTRIBUTORS.txt](CONTRIBUTORS.txt) in this directory. Local modifications
are limited to the subset extraction and SwiftTUI's strict-memory-safety and
platform-conditional import conventions.
