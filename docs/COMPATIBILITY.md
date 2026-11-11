# Compatibility policy

This repository versions independently. From 0.21.0 onward, supported contracts
remain source- and behavior-compatible until the next major version. Compatible
fixes use patch releases; compatible features use minor releases. A breaking
change requires a major release (1.0.0 for the current 0.x line), migration
guidance and release qualification. Deprecations retain declarations and behavior
through the current major line. The 0.21.0 floor remains protected across later
0.x minors; a new minor does not reset the compatibility baseline.

This promise covers supported public APIs and ratified SPI equally, including
Host, Testing and StyleFixtures where provided. It preserves signature-reachable
types, actor/Sendable and generic requirements, default witnesses, documented
behavior, and platform/toolchain minimums. Swift contracts cover source rebuilt
with the supported toolchain/platform set, not a cross-toolchain precompiled ABI.
Wire, WASM and Android C/JNI profiles remain separately named contracts; a package
minor must preserve existing clients of its supported profiles. Adding an optional
capability is compatible; removing a required operation or changing its meaning is
not. Matching repository version numbers never establish compatibility.

Unratified implementation SPI, private engine inspection and explicitly experimental
tooling remain outside this promise. Their tests use the exact versions recorded
in committed lockfiles or an explicitly qualified coordination overlay. A manifest
range does not make these interfaces stable. Updating such tooling's lockfile
requires rerunning its tests and may require adapting that tooling.

Supported Swift sibling dependencies use `.upToNextMajor(from: "0.21.0")` (or a
later qualified floor): 0.21.0 inclusive through 1.0.0 exclusive. Each consumer
owns its minimum version and lockfile. Compatible provider releases require no
consumer release, synchronized version bump, or website update. Frozen release
fixtures, bundled distribution bytes, Maven/plugin selections and curated site
inputs may retain exact identities for reproducibility; they do not impose
lockstep releases. The site curates its own deployment tuple.
