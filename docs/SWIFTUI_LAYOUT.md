# SwiftUI Layout

This document is a high-level, implementation-oriented explanation of how SwiftUI layout works. It focuses on the algorithm, the participating entities, and the different ways views participate in layout, rather than trying to catalog every built-in view type.

The short version:

- SwiftUI layout is a recursive negotiation, not a global constraint solve.
- A parent proposes a size.
- A child chooses its own size in response to that proposal.
- The parent then places the child within its bounds.
- Containers repeat this process for their children, often making multiple measurements before they decide.

That mental model is the core of almost everything else.

## 1. The Core Mental Model

Apple has described SwiftUI layout since WWDC19 as a parent-child interaction with three fundamental steps:

1. A parent offers a proposed size to a child.
2. The child returns the size it wants.
3. The parent places the child.

The important consequence is that, in SwiftUI, views own their sizing behavior. A parent can influence a child by making a proposal, but it does not directly impose a final size the way a traditional constraint system might. Even something like `frame(...)` is best understood as another view in the tree that participates in the same negotiation.

Two immediate implications follow from this:

- Layout is local and compositional. The behavior of the whole interface emerges from many small parent-child negotiations.
- The same view can report different sizes under different proposals. There is no single universal size for most views.

## 2. The Main Phases

It helps to think about SwiftUI layout as happening in five conceptual phases.

### 2.1 Resolve the Content Tree

Before layout can happen, SwiftUI has to determine which subviews actually exist at runtime.

This is more subtle than it looks in source code:

- Some declared views directly correspond to onscreen subviews.
- Some declared views are structural only and resolve into other subviews.
- Some declared views resolve into zero, one, or many runtime subviews depending on data or conditions.

WWDC24 formalized this distinction as:

- Declared subviews: what appears in code.
- Resolved subviews: what the container actually lays out at runtime.

Examples of structural producers include `ForEach`, `Group`, `Section`, conditional branches, and `EmptyView`. These are not interesting because of their visual appearance; they are interesting because they affect what a container actually receives as layout children.

This distinction matters because layout is performed on the resolved content, not on the source-level syntax alone.

### 2.2 Proposal

Layout starts when some container has bounds to work with and proposes a size to its child or children.

A proposal is not a command. It is an offer or suggestion:

- "You may use up to this much width and height."
- "Tell me what size you would like under these conditions."

At the root of the hierarchy, the proposal usually starts from the safe-area-adjusted available region of the host platform.

In the custom `Layout` API, this proposal is represented by `ProposedViewSize`, whose width and height can each be specified or unspecified. SwiftUI also uses special proposals such as:

- `.zero`: useful for learning a minimum-like response.
- `.unspecified`: useful for learning an ideal size.
- `.infinity`: useful for learning a maximum-like response.

Those are not magical "true" intrinsic sizes. They are probes that let a parent learn how a child behaves under different conditions.

### 2.3 Measurement

After receiving a proposal, a child computes the size it wants and returns a concrete size.

This is the measurement phase.

Crucially, a parent is free to measure the same child more than once with different proposals before deciding what to do. This is explicit in the `Layout` protocol design:

- `LayoutSubview.sizeThatFits(_:)` asks for size only.
- `LayoutSubview.dimensions(in:)` asks for size plus alignment information.

This means SwiftUI layout is not always a single top-to-bottom pass. A container may:

1. Probe children for ideal sizes.
2. Probe them again for minimum or maximum behavior.
3. Compare flexibility, spacing, and priorities.
4. Only then compute the container's own final size.

Stacks are the classic example. Apple has explained them as first accounting for spacing, then allocating remaining space among siblings according to flexibility and priority, measuring children as needed to discover how much space they actually claim.

### 2.4 Placement

Once a parent knows its own size and the chosen sizes of its children, it places them.

Placement answers questions like:

- Where is each child's origin?
- Which anchor is aligned to that point?
- How are children aligned relative to one another?
- How is extra or missing space distributed?

In a custom `Layout`, this is exposed as `placeSubviews(in:proposal:subviews:cache:)`. The `bounds` rectangle passed in is the region the layout asked for during measurement. The layout then positions each subview inside that rectangle.

Placement is separate from measurement. A child can be measured under one proposal and placed later using a placement proposal and anchor that reflect the parent's final decision.

### 2.5 Rendering Cleanup

Apple has also called out a final detail that developers often do not think of as "layout" but that matters visually: SwiftUI rounds view geometry to pixel boundaries so edges render crisply.

This is not the main algorithm, but it is part of why SwiftUI layouts often look cleaner than a naive float-based placement system.

## 3. The Main Entities That Participate

The most useful way to understand SwiftUI layout is by role, not by concrete type name.

### 3.1 The Root Host

At the top there is always some host: a platform view, scene, window, or hosting container. It establishes the initial available region and kicks off layout.

Responsibilities:

- Establish initial bounds.
- Respect safe areas unless overridden.
- Trigger relayout when environment or state changes.

### 3.2 Leaf Views

Leaf views are views whose layout behavior is mostly about answering "How big do I want to be under this proposal?"

Examples include text, images, shapes, controls, and representable platform views.

Responsibilities:

- Compute a concrete size from a proposal.
- Possibly expose alignment information.
- Draw themselves inside the size they chose.

Key point: leaf views are not all the same. Some are very compliant, some are highly opinionated, and some have proposal-dependent behavior that changes dramatically with width, height, text wrapping, or aspect ratio.

### 3.3 Layout-Neutral Wrappers

Some views mainly relay layout behavior rather than introducing a new size policy of their own.

Apple described the top layer of a view with a `body` as layout-neutral: its bounds are defined by the bounds of its body. In other words, some nodes in the tree are mostly structural composition rather than independent layout decisions.

A layout-neutral participant typically:

- Forwards the proposal to its content.
- Reports the content's size back upward.
- Adds little or nothing to the size calculation itself.

These are important because SwiftUI view trees contain a lot of structure that is semantically meaningful in code but mostly transparent to layout.

### 3.4 Layout-Transforming Wrappers

Other wrappers are not neutral. They transform either the proposal sent downward, the size reported upward, or both.

This is where many common modifiers live conceptually.

Examples of behaviors in this category:

- A wrapper subtracts padding from the incoming proposal before measuring its child, then adds padding back to the reported size.
- A wrapper proposes constrained dimensions to a child, then places the child within a larger or smaller enclosing frame.
- A wrapper asks its primary child for size, then gives the resulting size to a secondary decoration child such as a background.

This is the right way to think about many modifiers: not as imperative flags, but as additional layout-participating nodes in the hierarchy.

### 3.5 Multi-Child Containers

Containers are where layout policy becomes most visible.

A multi-child container:

- Receives a proposal from its parent.
- Measures some or all of its children, often multiple times.
- Decides how much space each child gets.
- Computes its own size.
- Places the children.

Common container jobs:

- Linear distribution along an axis.
- Two-dimensional placement.
- Overlaying or stacking in depth.
- Choosing one of several candidate layouts.
- Transforming resolved subviews into container-specific structure.

What matters is not whether the container is called `HStack`, `Grid`, `ZStack`, or something custom. What matters is the kind of policy it implements.

### 3.6 Custom `Layout` Types

Since iOS 16/macOS 13, SwiftUI exposes direct participation in the engine through the `Layout` protocol. This is not a different layout system; it is SwiftUI exposing the same kind of container role that built-in layout containers already play.

A custom `Layout` gets:

- A proposal from its own parent.
- A proxy collection for its subviews.
- A way to measure those subviews.
- A way to place them.
- Optional cache hooks.

This is the clearest public window into how SwiftUI layout is designed internally.

### 3.7 Structural Content Producers

Some participants matter because they change the shape of the child collection a container sees.

These include:

- `ForEach`
- `Group`
- `Section`
- conditional branches
- `EmptyView`

They are often not "layouts" themselves. Their job is to define or transform the resolved subview set.

This matters because containers lay out resolved subviews, not source tokens.

### 3.8 Metadata Participants

Some entities do not primarily determine size, but still influence layout decisions:

- alignment guides
- spacing preferences
- layout priority
- layout values
- container values

These act like side-channel metadata that containers can consult while measuring and placing children.

## 4. How Different Participants Behave

The most important differences between participants are not their names, but which part of the negotiation they influence.

### 4.1 Some Mainly Answer Size; Others Mainly Allocate Space

Leaf-like views mainly answer:

- "Given this proposal, I want to be this size."

Containers mainly answer:

- "Given this proposal and these children, I will allocate space like this."

That distinction separates local sizing behavior from sibling coordination behavior.

### 4.2 Some Are Neutral; Others Rewrite the Negotiation

A layout-neutral wrapper mostly preserves its child's behavior.

A layout-transforming wrapper can:

- shrink the proposal before forwarding it
- replace unspecified dimensions with explicit ones
- clamp a child's answer
- add extra area around the child
- align the child within an enclosing rectangle

This is why modifier order matters. Each wrapper changes the negotiation context for the next one.

### 4.3 Some Are Compliant; Others Are Opinionated

Not all views respond to proposals with the same attitude.

At a high level, views often fall somewhere along this spectrum:

- Highly compliant: they more or less accept the offered size.
- Ideal-size driven: they prefer a content-based size and only expand or shrink in specific ways.
- Fixed or nearly fixed: they resist change and report essentially the same size under many proposals.
- Flexible-but-constrained: they can stretch or compress, but only according to their own rules.

Apple's docs and talks repeatedly emphasize that views choose their own size. The practical outcome is that "offered size" and "actual chosen size" are often different.

### 4.4 Some Produce One Child; Others Produce Many Resolved Children

A single wrapper with one child behaves very differently from a structural producer like `ForEach` or `Group`.

One-child wrappers create a chain of negotiations.
Structural producers change the set of siblings that a container has to reason about.

That difference is why "declared subviews" versus "resolved subviews" matters for understanding containers.

### 4.5 Some Preserve Identity Across Layout Changes

Adaptive containers such as `AnyLayout` and `ViewThatFits` are important because they participate differently:

- `AnyLayout` switches which layout policy is used while preserving subview identity and enabling smooth transitions between layout strategies.
- `ViewThatFits` measures candidates and chooses the first one that fits the available space.

These are not just convenience APIs. They expose two important SwiftUI ideas:

- layout policy can itself be dynamic
- choosing a layout is also a layout operation

## 5. Proposal Semantics in More Detail

`ProposedViewSize` is one of the most important public clues to the engine design.

### 5.1 A Proposal Is Partial

Width and height can be independently specified or unspecified.

That means a parent can say things like:

- "Here is a width; pick your own height."
- "Tell me your ideal size."
- "How small can you be?"
- "How large could you become?"

This is much more expressive than a single fixed rectangle.

### 5.2 Parents Can Probe for Flexibility

The custom layout APIs explicitly support asking subviews multiple questions:

- minimum-like behavior via `.zero`
- ideal behavior via `.unspecified`
- maximum-like behavior via `.infinity`

A container can compare those answers to learn:

- whether a child is rigid or flexible
- how much a child can compress
- how much it can expand
- which children should receive scarce or extra space first

This is a key reason SwiftUI layout feels local and algorithmic rather than solver-based.

### 5.3 There Is No Single "Intrinsic Size" Story

UIKit developers often look for a direct equivalent to intrinsic content size. In SwiftUI, that intuition only partially transfers.

SwiftUI certainly has the concept of ideal size, but:

- it is proposal-dependent
- parents can ask for different kinds of answers
- wrappers and modifiers can transform the result
- containers may prioritize one answer over another depending on policy

So the better mental model is not "every view has one true size." The better model is "every view exposes sizing behavior."

## 6. Measurement Is Separate From Placement

This separation is fundamental.

During measurement, the question is:

- How large should this thing be?

During placement, the question is:

- Where should this thing go inside the available region?

Why this matters:

- A child can be measured several times before final placement.
- Alignment is mostly a placement concern, though alignment data is learned during measurement.
- A parent may know a child's size long before it knows that child's final position.

This is especially visible in custom layouts:

- `sizeThatFits(...)` computes required size.
- `placeSubviews(...)` performs final positioning.

That split is one of the cleanest design choices in SwiftUI layout.

### 6.1 Geometry-Dependent Content Uses Placement Geometry

`GeometryReader` follows the measurement/placement split. It participates in
measurement with an explicit flexible sizing policy, but its authored content is
realized only after layout has assigned concrete bounds. `GeometryProxy.size`
therefore describes the reader's placed geometry, not a resolve-time
`EnvironmentValues.terminalSize` guess.

This matters for custom `Layout`: a parent may measure a reader under one
proposal and later place it under another. The proxy should reflect the
placement proposal and final bounds. Measuring the reader is not allowed to
commit lifecycle, task, gesture, command, drop, or semantic side effects from
the reader's content.

## 7. Alignment, Spacing, and Priority

These are not separate subsystems. They are metadata that feed the same measurement-and-placement algorithm.

### 7.1 Alignment Guides

Alignment guides let a child expose reference lines or points that a parent can use during placement.

`ViewDimensions` carries:

- width
- height
- alignment guides in the view's own coordinate space

Containers can read those guides and line siblings up on a shared reference, including custom guides that project through nested containers.

So alignment is not "move this child by a magic offset." It is "children expose anchors that parents use while placing them."

### 7.2 Spacing Preferences

SwiftUI subviews also expose preferred spacing. Custom layouts can read `ViewSpacing` values from subview proxies and compute distances between adjacent children.

This is important because spacing is not always just a hard-coded constant. The framework can preserve platform-appropriate defaults unless the container deliberately overrides them.

### 7.3 Layout Priority

`layoutPriority` changes how a parent allocates scarce or abundant space among siblings.

Apple's stack explanation is especially useful here: when children have different priorities, lower-priority children can effectively have space reserved differently than higher-priority children, changing which sibling gets compressed first or expanded first.

This means `layoutPriority` is not a size by itself. It is an input to a container's allocation policy.

## 8. Common Modifier Behaviors in Layout Terms

Instead of memorizing one-off rules, it is better to interpret modifiers by what they do to the proposal/response/placement cycle.

### 8.1 `padding`

Conceptually:

1. Receive proposal.
2. Reduce proposal by the padding inset.
3. Measure child.
4. Add the padding back to the reported size.
5. Place child inset within the padded bounds.

### 8.2 `frame(...)`

`frame` is often misunderstood. Apple explicitly describes it as not being a constraint system equivalent. A frame is another layout participant.

Conceptually, a frame may:

- alter the proposal sent to its child
- adopt a size based on its own min/ideal/max rules
- place the child within the resulting rectangle according to alignment

This is why a child can remain smaller than its frame.

### 8.3 `fixedSize(...)`

`fixedSize` biases the negotiation toward a view's ideal size along selected axes. In practice, it tells the view hierarchy to preserve that ideal size even when the surrounding context is smaller, which can lead to overflow or reduced compression.

So `fixedSize` is not "make me this exact size." It is "prefer my ideal measured size over being compressed along these axes."

### 8.4 `background` and `overlay`

These are good examples of wrappers that often do not determine size from the decoration child.

Conceptually:

- measure the primary content
- adopt that size
- give that size to the decoration child for placement

This is why a background usually follows the size of the content it decorates.

## 9. Containers as Algorithms

The most useful abstraction for containers is not "row", "column", or "grid". It is algorithm.

A container algorithm typically does some combination of:

1. Normalize or transform the incoming proposal.
2. Determine spacing/alignment rules.
3. Probe children for one or more sizes.
4. Rank or group children by flexibility or priority.
5. Allocate available space.
6. Report the container's own size.
7. Place the children.

Apple's stack explanation from WWDC19 is a canonical example of this style:

- subtract spacing first
- divide remaining space among yet-unmeasured siblings
- measure the least flexible child
- subtract what that child actually takes
- repeat until every child has a size
- then align and place them

The important point is that a container is free to be strategic. It is not required to do naive left-to-right measurement.

## 10. Custom Layout Participation

The `Layout` protocol makes SwiftUI's layout model especially concrete.

### 10.1 `sizeThatFits`

This method answers:

- "Given the parent's proposal and my subviews, what size should I be?"

The layout can inspect subviews by proxy and ask each one for sizes under one or many proposals.

### 10.2 `placeSubviews`

This method answers:

- "Given the bounds I received, where do the subviews go?"

The layout uses `subview.place(...)` with points, anchors, and proposals.

### 10.3 `makeCache` and `updateCache`

SwiftUI recognizes that measurement can be expensive, so custom layouts can maintain a cache.

The important conceptual point is not just performance. It reveals that layout is expected to be recomputed as state changes, and that SwiftUI distinguishes:

- stable derived data worth caching
- transient results that should be recomputed

If `updateCache` is not implemented, SwiftUI rebuilds the cache from `makeCache`. If it is implemented, the layout can update incrementally when subviews or layout inputs change.

### 10.4 Layout Values

Custom layouts can also consult layout values attached to subviews. This lets children expose container-specific metadata without becoming coupled to a specific concrete parent type.

That is another recurring SwiftUI pattern:

- values flow through the tree
- containers read only the values relevant to their own policy

## 11. A Useful Taxonomy of Participation

If you want a compact way to classify how any SwiftUI view affects layout, use this checklist.

### 11.1 Does it define resolved subviews?

If yes, it is participating structurally.

### 11.2 Does it forward the proposal unchanged?

If yes, it is mostly layout-neutral.

### 11.3 Does it transform the proposal or returned size?

If yes, it is a layout-transforming wrapper.

### 11.4 Does it coordinate siblings?

If yes, it is functioning as a container algorithm.

### 11.5 Does it expose metadata like alignment, spacing, or priority?

If yes, it is influencing parent policy indirectly.

### 11.6 Does it measure children multiple times before deciding?

If yes, it is acting as a sophisticated container rather than a simple pass-through.

## 12. What SwiftUI Layout Is Not

Understanding SwiftUI is easier if you are also clear about what it is not.

### 12.1 Not a Global Auto Layout Constraint Solve

SwiftUI layout is not primarily a system of solving simultaneous equations over the entire tree.

Instead, it is recursive local negotiation:

- parent proposes
- child answers
- parent places

This makes behavior more compositional and usually easier to reason about once you adopt the correct mental model.

### 12.2 Not a System Where Parents Fully Control Child Size

Parents influence children through proposals and policy, but children still choose their size. This is why "force" is usually the wrong word in SwiftUI layout discussions.

### 12.3 Not Just About Concrete View Types

The same visible result can often be built from different combinations of:

- structural producers
- wrappers
- containers
- metadata

So understanding roles is more valuable than memorizing built-in type behavior in isolation.

## 13. Practical Consequences

These are the behaviors that fall directly out of the model above.

### 13.1 Modifier Order Matters

Because modifiers often create wrapper views that transform proposals and placement, changing order changes the layout tree and therefore changes behavior.

### 13.2 A View's Size Depends on the Question Asked

A child may return different answers for ideal, minimum-like, and maximum-like probes. Do not assume one call tells the whole story.

### 13.3 Layout and Identity Are Related but Separate

APIs like `AnyLayout` show that SwiftUI can change layout policy while preserving the identity of subviews. Layout is a behavior around views, not necessarily a redefinition of which views they are.

### 13.4 Decorations Often Follow Content Size

Backgrounds, overlays, and similar wrappers often inherit the measured size of their primary content rather than determining size independently.

### 13.5 Custom Layouts Are First-Class

The public `Layout` protocol is not an escape hatch around SwiftUI. It is SwiftUI's own layout model made available to developers.

## 14. A Compact End-to-End Example

A useful generic trace looks like this:

```text
Root host gets available bounds
-> proposes size to outer wrapper
-> wrapper transforms proposal and asks child
-> child container probes several subviews
-> subviews return different sizes
-> container computes spacing, priorities, and final allocation
-> container reports its chosen size upward
-> parent decides final bounds
-> parent places container
-> container places subviews
-> SwiftUI snaps geometry for crisp rendering
```

That is the shape of the engine, regardless of whether the concrete view tree is simple or sophisticated.

## 15. Bottom Line

The deepest correct mental model for SwiftUI layout is:

- SwiftUI layout is a recursive proposal-measure-place system.
- Views expose sizing behavior, not just fixed sizes.
- Modifiers often become layout participants.
- Containers are algorithms that allocate space among resolved subviews.
- Alignment, spacing, priority, and layout values are metadata that feed those algorithms.
- The `Layout` protocol is the public expression of this design.

If you internalize those points, most SwiftUI layout behavior becomes much easier to predict.

## 16. Official References

Primary sources used for this write-up:

- [Building Custom Views with SwiftUI (WWDC19)](https://developer.apple.com/videos/play/wwdc2019/237/)
- [Compose custom layouts with SwiftUI (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10056/)
- [Demystify SwiftUI containers (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10146/)
- [Layout](https://developer.apple.com/documentation/swiftui/layout)
- [ProposedViewSize](https://developer.apple.com/documentation/swiftui/proposedviewsize)
- [LayoutSubview.dimensions(in:)](https://developer.apple.com/documentation/swiftui/layoutsubview/dimensions(in:))
- [ViewDimensions](https://developer.apple.com/documentation/swiftui/viewdimensions)
- [frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)](https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:))
- [fixedSize(horizontal:vertical:)](https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:))
- [layoutPriority(_:)](https://developer.apple.com/documentation/swiftui/view/layoutpriority(_:))
- [AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)
- [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)
- [Composing custom layouts with SwiftUI](https://developer.apple.com/documentation/swiftui/composing_custom_layouts_with_swiftui)
- [Layout modifiers](https://developer.apple.com/documentation/swiftui/view-layout)

## 17. TerminalUI Implementation Status

This document is the SwiftUI layout model reference — the target that TerminalUI's layout engine aims to match.

For current implementation status, known gaps, and next steps, see [STATUS.md](STATUS.md).
