# ``SwiftTUIGraph``

The reconciliation engine — SwiftTUI's AttributeGraph analog — plus the runtime
registries and semantic vocabulary that ride on it.

## Overview

`SwiftTUIGraph` owns the resolved view tree and everything that decides *what
changed*: state slots, dependency tracking, invalidation planning, reuse gates,
checkpoints, entity routing, the scheduler, and animation intent.

```
SwiftTUIPrimitives -> SwiftTUIGraph -> SwiftTUICore -> SwiftTUIViews -> SwiftTUIRuntime
```

It depends on `SwiftTUIPrimitives` **only**. That constraint is deliberate and
compiler-enforced: graph code names no render type, so reconciliation can be
tested and reasoned about without a frame pipeline. The module is
Foundation-free.

You rarely import this module directly — `SwiftTUICore` `@_exported`-imports it,
so the types below are already in scope from `SwiftTUIViews` or `SwiftTUI`. This
reference exists because parts of the graph's vocabulary surface in public
authoring APIs: preference keys, focused values, key events, and the
matched-geometry namespace.

For the normative reconciliation model — dirty frontiers, cones, freshness
stamps, the two-layer reuse door, and its soundness oracles — see
<doc:Reuse-and-Invalidation>.

## Topics

### Reconciliation

- <doc:Reuse-and-Invalidation>

### Preferences And Anchors

- ``PreferenceKey``
- ``Anchor``
- ``AnchorSource``

### Focus And Focused Values

- ``FocusedValueKey``
- ``FocusedValues``
- ``FocusRegion``

### Matched Geometry

- ``MatchedGeometryNamespace``
- ``MatchedGeometryKey``
- ``MatchedGeometryConfig``

### Keyboard Input

- ``KeyEvent``
- ``KeyPress``
- ``KeyPressResult``
- ``EventModifiers``

### Semantic Routing

- ``RouteID``
- ``RouteKind``
- ``ScrollRoute``
- ``ScrollRole``
- ``SectionRole``

### Accessibility

- ``AccessibilityNode``
- ``AccessibilityRole``
- ``AccessibilityPoliteness``

### Scheduling And Lifecycle

- ``FrameScheduling``
- ``ScheduledFrame``
- ``WakeCause``
- ``Invalidating``
- ``NodeLifecycleInfo``
- ``TaskDescriptor``
- ``TaskPriority``

### Diagnostics

- ``RuntimeIssue``
- ``RuntimeIssueSeverity``
- ``RuntimeIssueSink``
- ``TerminationRequest``
- ``TerminationDisposition``
