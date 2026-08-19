# ``SwiftTUIGraph``

The reconciliation engine, SwiftTUI's AttributeGraph analog, plus the runtime
registries and semantic vocabulary that ride on it.

## Overview

> Note: This is an engine layer. Apps do not import it directly — its
> app-facing vocabulary (such as ``DynamicProperty``, ``PreferenceKey``, and
> ``KeyPress``) arrives through `import SwiftTUI` or any other authoring
> product. Start from the
> [`SwiftTUI` module](https://swifttui.sh/docs/documentation/swifttui) unless
> you are working on the framework itself.

`SwiftTUIGraph` owns the resolved view tree and the mechanisms that decide *what
changed*. These mechanisms include state slots, dependency tracking,
invalidation planning, reuse gates, checkpoints, and entity routing. They also
include the scheduler and animation intent.

```
SwiftTUIPrimitives -> SwiftTUIGraph -> SwiftTUICore -> SwiftTUIViews -> SwiftTUIRuntime
```

It depends on `SwiftTUIPrimitives` **only**. The compiler enforces this
constraint. Graph code names no render type. Thus, reconciliation tests do not
require a frame pipeline. The module is Foundation-free.

You rarely import this module directly. `SwiftTUICore` `@_exported`-imports it.
Thus, `SwiftTUIViews` and `SwiftTUI` already provide the types below. Parts of
the graph vocabulary occur in public authoring APIs. These parts include
preference keys, focused values, key events, and the matched-geometry namespace.

For the normative reconciliation model, see <doc:Reuse-and-Invalidation>. It
defines dirty frontiers, cones, freshness stamps, the two-layer reuse door,
and its soundness oracles.

## Topics

### Reconciliation

- <doc:Reuse-and-Invalidation>
- ``DynamicProperty``

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
