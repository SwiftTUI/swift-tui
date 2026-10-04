import SwiftTUICore

/// A compact progress bar with optional label and current-value content.
///
/// Publishes one read-only progress indicator, independent of its style. The
/// authored label names the task, the current-value label describes its value,
/// and determinate progress supplies a clamped fraction. Indeterminate progress
/// has no numeric value. Updates do not create live announcements by default.
public struct ProgressView<Label: View, CurrentValueLabel: View>: PrimitiveView,
  IterativeResolvableView
{
  public var value: Double
  public var total: Double
  public var barWidth: Int
  public private(set) var isIndeterminate: Bool
  private var label: Label
  private var currentValueLabel: CurrentValueLabel
  private let authoringScope: AuthoringContext?
  @State private var indeterminatePhase: UInt64 = 0

  /// Creates an indeterminate progress view with no label.
  public init(barWidth: Int = 12) where Label == EmptyView, CurrentValueLabel == EmptyView {
    authoringScope = currentAuthoringContext()
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    label = EmptyView()
    currentValueLabel = EmptyView()
  }

  /// Creates an indeterminate progress view with a label.
  public init<S: StringProtocol>(
    _ title: S,
    barWidth: Int = 12
  ) where Label == Text, CurrentValueLabel == EmptyView {
    authoringScope = currentAuthoringContext()
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    label = Text(String(title))
    currentValueLabel = EmptyView()
  }

  /// Creates an indeterminate progress view with a custom label.
  public init(
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label
  ) where CurrentValueLabel == EmptyView {
    authoringScope = currentAuthoringContext()
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    self.label = label()
    currentValueLabel = EmptyView()
  }

  public init(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) where Label == EmptyView, CurrentValueLabel == Text {
    authoringScope = currentAuthoringContext()
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
    label = EmptyView()
    currentValueLabel = Text(progressSummaryText(value: value, total: total))
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) where Label == Text, CurrentValueLabel == Text {
    authoringScope = currentAuthoringContext()
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
    label = Text(String(title))
    currentValueLabel = Text(progressSummaryText(value: value, total: total))
  }

  public init(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    authoringScope = currentAuthoringContext()
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
    self.label = label()
    self.currentValueLabel = currentValueLabel()
  }

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    withDynamicPropertyUpdateScope(self, for: context) {
      resolvedNode(in: context).map { [$0] }
    }
  }

  private func resolvedNode(in context: ResolveContext) -> ResolveWork<ResolvedNode> {
    let rawFraction = progressFraction(value: value, total: total)
    let fraction = rawFraction.isFinite ? rawFraction : 0
    let animates = isIndeterminate && !context.environmentValues.renderingReduceMotion
    let tasks: [TaskDescriptor]
    if animates {
      // Cadence belongs to the primitive so every style receives a live
      // phase, while standalone style fixtures remain inert.
      let descriptor = TaskDescriptor(
        id: "\(context.identity)#indeterminateProgress", priority: .userInitiated)
      let phase = $indeterminatePhase
      context.viewGraph?.recordLifecycleEvaluationOwner(
        target: context.identity, owner: context.identity)
      HandlerDescriptorIntake(context: context).registerTask(
        identity: context.identity, descriptor: descriptor
      ) {
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(120))
          guard !Task.isCancelled else { return }
          phase.wrappedValue &+= 1
        }
      }
      tasks = [descriptor]
    } else {
      tasks = []
    }
    let configuration = ProgressViewStyleConfiguration(
      fractionCompleted: isIndeterminate ? nil : fraction,
      label: isEmptyView(label)
        ? nil : .init(authoringContext: authoringScope) { label.authoredAccessibilityLabel() },
      currentValueLabel: isEmptyView(currentValueLabel)
        ? nil
        : .init(authoringContext: authoringScope) {
          currentValueLabel.authoredAccessibilityValueLabel()
        },
      barWidth: max(1, barWidth),
      indeterminatePhase: animates ? indeterminatePhase : 0,
      accessibilityReduceMotion: context.environmentValues.renderingReduceMotion,
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    var semantics = SemanticMetadata(accessibilityRole: .progressBar).namingControl(with: label)
    if isEmptyView(label) { semantics.accessibilityTitle = "Progress" }
    semantics.accessibilityControl = .init(
      actions: [], value: isIndeterminate ? nil : .number(fraction), minimum: 0, maximum: 1)
    let valueText = currentValueLabel as? Text
    semantics.accessibilityValueLabel = .owner(
      fallback: valueText.map {
        $0.semanticMetadata.accessibilityHidden
          ? "" : $0.semanticMetadata.accessibilityLabel ?? $0.content
      })
    return context.environmentValues.progressViewStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("ProgressViewBody"))
    ).map { child in
      return ResolvedNode(
        identity: context.identity,
        kind: .view("ProgressView"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: semantics,
        lifecycleMetadata: .init(tasks: tasks)
      )

    }
  }
}
