# Compatibility policy

This repository versions independently. Its supported 0.21.x contracts accept
compatible fixes, additions and implementation changes in patch releases.
Removing a supported declaration, changing its promised behavior, tightening
actor/Sendable or generic requirements, or raising a platform/toolchain minimum
requires a new minor version and migration guidance. Deprecations retain their
declarations and behavior through the current minor line. This is SwiftTUI's
explicit pre-1.0 policy; it does not promise indefinite maintenance of old lines.

The policy applies equally to documented supported public and SPI contracts.
Unratified implementation SPI and explicitly experimental tooling use exact
tested selections and make no automatic patch-compatibility promise. Swift
contracts cover rebuilding source with the documented toolchain/platform set,
not a cross-toolchain precompiled Swift ABI. Wire, WASM and Android C/JNI
profiles have separate named contracts. Matching repository versions do not
establish compatibility.

Dependencies and their supported lines belong to the native manifests. A new
dependency minor is an explicit consumer adoption; it does not force sibling
releases or a website update. The site curates its own deployment tuple.
