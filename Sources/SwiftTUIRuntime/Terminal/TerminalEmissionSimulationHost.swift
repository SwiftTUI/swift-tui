import SwiftTUICore

#if !canImport(WASILibc)
  /// An in-process presentation surface that runs the REAL terminal
  /// presentation planner and emission builder against a byte-counting sink —
  /// no tty, no writer thread.
  ///
  /// TermUIPerf's emission-visible lane (`SWIFTTUI_PERF_EMISSION=1`) installs
  /// it in place of the semantic-host perf surface, so `present_bytes`,
  /// `present_strategy`, and `present_sync` in `frames.tsv` (and the
  /// `summary.json` emission aggregates) carry the true emitted escape stream
  /// for perf scenarios instead of the structural zeros the semantic-host
  /// path reports. The planner + emission cost lands inside `present_ms` and
  /// `total_ms` — deliberately: that cost was the measurement blind spot.
  /// Because the lane both adds that cost and changes the advertised
  /// capability profile, lane-on runs are only comparable with lane-on runs.
  ///
  /// The capability profile is fixed and deterministic
  /// (``laneCapabilityProfile``): unicode glyphs, truecolor styling,
  /// hyperlinks on, synchronized output ON, kitty graphics OFF
  /// (`graphicsCapabilities == .none`), terminal edit-operation lowering
  /// (CSI K) ON. Byte counts for identical scenario content are therefore
  /// stable run to run.
  ///
  /// Baseline semantics reuse ``TerminalPresentationSession`` faithfully: the
  /// planner diffs against `lastWrittenSurface` and the damage hint flows
  /// through `presentationDamage(requested:)`. The sink is synchronous, so
  /// every emission "reaches the terminal": the prepared surface becomes the
  /// written baseline immediately, no frame can drop, and the trust latch
  /// never trips — which matches the run loop's previously-presented damage
  /// baseline exactly, keeping the hinted diffs honest.
  @_spi(Runners) public final class TerminalEmissionSimulationHost: PresentationSurface,
    DamageAwarePresentationSurface
  {
    /// The lane's fixed profile — see the type comment for the rationale.
    public static let laneCapabilityProfile = TerminalCapabilityProfile(
      glyphLevel: .unicode,
      colorLevel: .trueColor,
      emitsStyleEscapeSequences: true,
      supportsHyperlinks: true,
      supportsMouseReporting: true,
      supportsSynchronizedOutput: true
    )

    public let surfaceSize: CellSize
    public let capabilityProfile: TerminalCapabilityProfile
    public let appearance: TerminalAppearance
    public var theme: Theme? { nil }
    public let graphicsCapabilities: TerminalGraphicsCapabilities = .none
    public let pointerInputCapabilities: PointerInputCapabilities

    /// Called after every present with the presented surface and the metrics
    /// the real planner + emission builder produced, so an external frame
    /// recorder (the perf host) keeps its presented-frame log without owning
    /// any emission logic.
    private let onPresent: (RasterSurface, TerminalPresentationMetrics) -> Void

    private var presentationSession = TerminalPresentationSession()
    private let imageRenderer = TerminalImageRenderer(repository: sharedImageAssetRepository)

    public init(
      surfaceSize: CellSize,
      capabilityProfile: TerminalCapabilityProfile = laneCapabilityProfile,
      appearance: TerminalAppearance = .fallback,
      pointerInputCapabilities: PointerInputCapabilities = .cellOnly,
      onPresent: @escaping (RasterSurface, TerminalPresentationMetrics) -> Void
    ) {
      self.surfaceSize = surfaceSize
      self.capabilityProfile = capabilityProfile
      self.appearance = appearance
      self.pointerInputCapabilities = pointerInputCapabilities
      self.onPresent = onPresent
    }

    public func enableRawMode() throws {}
    public func disableRawMode() throws {}
    public func write(_: String) throws {}
    public func clearScreen() throws {}
    public func moveCursor(to _: CellPoint) throws {}
    public func setPointerHoverEnabled(_: Bool) throws {}

    @discardableResult
    public func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
      try present(surface, damage: nil)
    }

    @discardableResult
    public func present(
      _ surface: RasterSurface,
      damage: PresentationDamage?
    ) throws -> TerminalPresentationMetrics {
      let preparedSurface = imageRenderer.preparedSurface(
        for: surface,
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities,
        fallbackBackground: appearance.backgroundColor
      )
      let plan = TerminalPresentationPlanner(
        capabilityProfile: capabilityProfile,
        graphicsCapabilities: graphicsCapabilities,
        terminalBackgroundColor: appearance.backgroundColor
      ).plan(
        previousSurface: presentationSession.previousSurface,
        currentSurface: preparedSurface,
        damage: presentationSession.presentationDamage(requested: damage)
      )
      presentationSession.requestedDamageTrustsBaseline = true

      let emissionBuilder = TerminalHostPresentationEmissionBuilder(
        capabilityProfile: capabilityProfile,
        usesTerminalEditOperations: true,
        imageRenderer: imageRenderer,
        fallbackBackground: appearance.backgroundColor,
        terminalBackgroundColor: appearance.backgroundColor
      )
      var transmittedKittyImages = presentationSession.transmittedKittyImages
      var residentKittyImageData = presentationSession.residentKittyImageData
      let emission = emissionBuilder.build(
        for: preparedSurface,
        plan: plan,
        graphicsCapabilities: graphicsCapabilities,
        transmittedKittyImages: &transmittedKittyImages,
        residentKittyImageData: &residentKittyImageData
      )
      presentationSession.transmittedKittyImages = transmittedKittyImages
      presentationSession.residentKittyImageData = residentKittyImageData

      let usedSynchronizedOutput = TerminalHostEscapeSequences.usesSynchronizedOutput(
        for: emission.output,
        plan: plan,
        capabilityProfile: capabilityProfile
      )
      let bufferedOutput = TerminalHostEscapeSequences.wrappedSynchronizedOutput(
        emission.output,
        plan: plan,
        capabilityProfile: capabilityProfile
      )
      // Synchronous sink: the emission cannot be dropped, so the prepared
      // surface is the written baseline the moment its bytes are counted.
      presentationSession.lastWrittenSurface = preparedSurface

      let metrics = emission.metrics(
        for: plan,
        output: bufferedOutput,
        usedSynchronizedOutput: usedSynchronizedOutput
      )
      onPresent(surface, metrics)
      return metrics
    }
  }
#endif
