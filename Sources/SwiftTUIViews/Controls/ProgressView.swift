import SwiftTUICore

/// A compact progress bar with optional label and current-value content.
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
    let fraction = progressFraction(value: value, total: total)
    let animates = isIndeterminate && !context.environmentValues.renderingReduceMotion
    var tasks: [TaskDescriptor] = []
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
      tasks.append(descriptor)
    }
    let configuration = ProgressViewStyleConfiguration(
      fractionCompleted: isIndeterminate ? nil : (fraction.isFinite ? fraction : 0),
      label: isEmptyView(label)
        ? nil : .init(authoringContext: authoringScope) { label.authoredAccessibilityLabel() },
      currentValueLabel: isEmptyView(currentValueLabel)
        ? nil : .init(authoringContext: authoringScope) { currentValueLabel },
      barWidth: max(1, barWidth),
      indeterminatePhase: animates ? indeterminatePhase : 0,
      accessibilityReduceMotion: context.environmentValues.renderingReduceMotion,
      styleEnvironment: context.environmentValues.styleEnvironmentSnapshot
    )
    return context.environmentValues.progressViewStyle.resolveBody(
      configuration: configuration, in: context.child(component: .named("ProgressViewBody"))
    ).map { child in
      return ResolvedNode(
        identity: context.identity,
        kind: .view("ProgressView"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        semanticMetadata: SemanticMetadata(accessibilityRole: .status).namingControl(with: label),
        lifecycleMetadata: .init(tasks: tasks)
      )

    }
  }
}
