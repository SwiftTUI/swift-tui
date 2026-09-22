# Canonical draw diagnostics, version 1

`SnapshotRenderer.canonicalDrawTree` extends the existing tree printer with a
lossless structural value record for supported draw payloads. Its companion
`canonicalDrawDifference` reports changed line numbers and before/after text.
These are package diagnostic APIs; normal draw traversal and rasterization do
not call them.

Run the connected diagnostic comparison:

```sh
swiftly run swift test --build-system native --filter CanonicalDrawSnapshotTests/diagnosticComparison
```

It rasterizes two different fills, verifies their surfaces differ, and emits
the expected/actual canonical artifacts and their line diff. The full
`CanonicalDrawSnapshotTests` filter also covers equivalence and adversarial
composition changes. Tests run in the normal Core lane.

## Normalization contract

The header is `SwiftTUI canonical draw v1`. Child arrays, command arrays,
post-child commands and draw effects retain their exact order. Identity
components, geometry, node and command clipping, metadata, styles, gradient
contents, floating-point bit patterns, image bytes/references/identity/opacity,
and composition remain represented. Existing value formatters provide readable
command labels; structural records preserve values abbreviated by those labels.
Strings are escaped, including embedded newlines and delimiters.

Only these incidental values are omitted:

- `viewNodeID`, an allocation-local graph handle;
- the per-process cached identity hash, replaced by exact identity components;
- derived subtree bounds/count/mask aggregates, recoverable from the tree;
- environment debug signatures and non-style bookkeeping. Rasterization reads
  the captured style environment, which is retained in full.

The equivalence fixture varies allocation IDs and environment bookkeeping and
checks both identical canonical output and complete `RasterSurface` equality.
No wrapper nodes, commands or semantic image identities are erased. The format
is deliberately stricter than pixel equality: equal pixels do not require equal
artifacts. Dictionary/set storage is ordered only where the value itself is
unordered; paint sequences are never sorted.

Closed value records use reflected field labels, with explicit unboxing for
the immutable style/metadata/path storage and explicit identity normalization.
An unsupported reference or opaque value throws instead of emitting its memory
address or falsely claiming equivalence. In particular, user `CanvasDrawing`
implementations and live foreign-surface payloads are unsupported in version 1,
including when nested inside a command group. Their existing concise snapshots
remain available, but are not canonical-equivalence claims.

This is an internal, versioned debugging schema, not a public serialization
ABI. Reflected field-layout/type-spelling changes require format review and
may require a version bump. Compare artifacts from the same fixture/framework
schema and record the toolchain when sharing them. The tests preserve meaningful
differences in paint and child order, post-paint, clipping, effects, gradient
colors, full text lines and overlapping image composition.
