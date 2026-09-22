# Public semantic differential fixtures, version 1

Run `python3 Scripts/run_public_semantics.py` on native macOS. Results, compiler
logs and a behavioral diff are written to `.build/public-semantics/`. The macOS
gate executes the comparison and uploads its artifacts. Linux records six
named unsupported skips for the Apple adapter; these are never counted as
passing parity. The SwiftTUI fixture itself also runs in the normal native tests.

Both adapters compile the exact same
`Tests/SwiftTUITests/PublicSemanticFixture.swift`, changing only the module
import. Inputs are captured public state/binding writes, followed by a host
update. Outputs are public `onChange`, `onAppear` and `onDisappear` callbacks
and their observed state values. No Apple private symbols, ABI assumptions,
body-evaluation counts or pixel comparisons enter the contract.

| Fixture | Inputs | Declared result |
| --- | --- | --- |
| State batching | Write 1, then 2 synchronously | Parity: one observed change to 2 |
| Equal-value writes | Write 0 over 0 | Parity: no observed change |
| Binding projection | Write `$pair.count = 3` | Parity: count 3, sibling 7 |
| Explicit identity reset | Increment; change `.id` | Ratified divergence: both reset, lifecycle order differs |
| AnyView same-type preservation | Increment; replace parent input at the same erasure boundary | Parity: state remains 1 |
| AnyView type-change teardown | Increment; replace erased concrete type at the same boundary | Ratified divergence: old leaf disappears, new state starts at 0; lifecycle order differs |

The SwiftTUI adapter drives the real run-loop commit harness, including
selective state invalidation and lifecycle dispatch. The Apple adapter uses
public `NSHostingView` and an AppKit window. After mounting and each action it
drives layout and the main run loop for a fixed 200 ms observation window.
This bounded window is part of fixture version 1; it is not a claim that
SwiftUI exposes a quiescence API. Failure to mount or install an action fails
the adapter. A 30-second process cap bounds the complete Apple run.

The checked-in `Scripts/data/public-semantic-v1.json` preserves each engine's
exact event order. SwiftTUI's existing disappearance-before-appearance contract
is pinned by its lifecycle planner and Core lifecycle tests; the macOS 27
Apple observation has the reverse order for the two replacement fixtures.
No event sorting hides that difference. See the published divergence register.

The result stamps fixture version and source hash, framework revision, macOS,
architecture, SDK, Xcode and Swift versions. Different OS/toolchain observations
remain reviewable; an oracle mismatch fails and prints a unified behavioral
diff. There is intentionally no automatic oracle-update option. To change the
contract, review the saved event sequences, explain the version/platform scope,
and edit the expected JSON explicitly.

Each run also checks that appending a deliberately incorrect expected event
is rejected. To independently replay or challenge the comparison:

```sh
python3 Scripts/run_public_semantics.py --compare-only .build/public-semantics/result.json --expected /tmp/reviewed-or-altered-expected.json --output .build/semantic-recheck
```

An altered expected event exits nonzero and produces `behavior.diff`. An
unsupported saved result cannot be replayed as a successful comparison.
