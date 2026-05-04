extension LayoutEngine {
  // MARK: - Intrinsic size helpers

  internal func measuredTextSize(
    for content: String,
    metadata: LayoutMetadata,
    proposal: ProposedSize
  ) -> CellSize {
    let wrapWidth: Int? =
      switch proposal.width {
      case .finite(let width):
        width
      case .unspecified, .infinity:
        nil
      }
    return layoutText(
      for: content,
      width: wrapWidth,
      lineLimit: metadata.lineLimit,
      truncationMode: metadata.textTruncationMode ?? .tail,
      wrappingStrategy: metadata.textWrappingStrategy ?? .wordBoundary
    ).size
  }

  internal func measuredTextFigureSize(
    for payload: TextFigurePayload,
    proposal: ProposedSize
  ) -> CellSize {
    TextFigureSupport.measuredSize(
      for: payload,
      proposal: proposal
    )
  }

  internal func measuredRuleSize(
    for proposal: ProposedSize,
    stackAxis: Axis?
  ) -> CellSize {
    let proposedWidth = finiteDimension(of: proposal.width)
    let proposedHeight = finiteDimension(of: proposal.height)

    if let stackAxis {
      switch stackAxis {
      case .vertical:
        let width = max(0, proposedWidth ?? 1)
        return CellSize(width: width, height: width > 0 ? 1 : 0)
      case .horizontal:
        let height = max(0, proposedHeight ?? 1)
        return CellSize(width: height > 0 ? 1 : 0, height: height)
      }
    }

    switch (proposedWidth, proposedHeight) {
    case (let width?, nil):
      return CellSize(width: max(0, width), height: width > 0 ? 1 : 0)
    case (nil, let height?):
      return CellSize(width: height > 0 ? 1 : 0, height: max(0, height))
    case (let width?, let height?):
      if width >= height {
        return CellSize(width: max(0, width), height: height > 0 ? 1 : 0)
      }
      return CellSize(width: width > 0 ? 1 : 0, height: max(0, height))
    case (nil, nil):
      return CellSize(width: 1, height: 1)
    }
  }

  internal func measuredShapeSize(
    for proposal: ProposedSize
  ) -> CellSize {
    CellSize(
      width: finiteDimension(of: proposal.width) ?? 0,
      height: finiteDimension(of: proposal.height) ?? 0
    )
  }

  internal func measuredImageSize(
    for payload: ImagePayload,
    proposal: ProposedSize
  ) -> CellSize {
    let intrinsicSize = payload.intrinsicCellSize
    guard payload.isResizable else {
      return intrinsicSize
    }

    let proposedWidth = finiteDimension(of: proposal.width)
    let proposedHeight = finiteDimension(of: proposal.height)

    switch payload.scalingMode {
    case .stretch:
      return CellSize(
        width: proposedWidth ?? intrinsicSize.width,
        height: proposedHeight ?? intrinsicSize.height
      )
    case .fit, .fill:
      guard
        let resolvedAsset = payload.resolvedAsset,
        resolvedAsset.pixelSize.width > 0,
        resolvedAsset.pixelSize.height > 0,
        resolvedAsset.cellPixelSize.width > 0,
        resolvedAsset.cellPixelSize.height > 0
      else {
        return CellSize(
          width: proposedWidth ?? intrinsicSize.width,
          height: proposedHeight ?? intrinsicSize.height
        )
      }

      // Aspect math has to happen in pixel space: the parent proposes a
      // frame in terminal cells, but terminal cells are rarely square
      // (typically 8x16 pixels), so a naïve `cells / pixels` scale factor
      // mixes units and distorts the image. Convert the proposed frame
      // into pixels, fit/fill against the source's pixel dimensions, and
      // then convert the result back to cells.
      let pixelSize = resolvedAsset.pixelSize
      let cellPixelWidth = Double(resolvedAsset.cellPixelSize.width)
      let cellPixelHeight = Double(resolvedAsset.cellPixelSize.height)
      let pixelAspect = Double(pixelSize.width) / Double(pixelSize.height)
      // Cell aspect of the source is what the frame proposer thinks the
      // image "looks like" — it folds the non-square cell ratio into the
      // aspect. Used for single-axis proposals.
      let cellAspect = pixelAspect * cellPixelHeight / cellPixelWidth

      // Fit rounds DOWN so the image fits strictly inside the frame;
      // fill rounds UP so the image fully covers it.
      let rounding: FloatingPointRoundingRule =
        payload.scalingMode == .fit ? .down : .up
      func cellsFromPixels(_ value: Double, per cellPixel: Double) -> Int {
        max(1, Int((value / cellPixel).rounded(rounding)))
      }

      switch (proposedWidth, proposedHeight) {
      case (let width?, let height?):
        guard width > 0, height > 0 else {
          return .zero
        }
        let framePixelWidth = Double(width) * cellPixelWidth
        let framePixelHeight = Double(height) * cellPixelHeight
        let widthScale = framePixelWidth / Double(pixelSize.width)
        let heightScale = framePixelHeight / Double(pixelSize.height)
        let scale =
          payload.scalingMode == .fit
          ? min(widthScale, heightScale)
          : max(widthScale, heightScale)
        let targetPixelWidth = Double(pixelSize.width) * scale
        let targetPixelHeight = Double(pixelSize.height) * scale
        return CellSize(
          width: cellsFromPixels(targetPixelWidth, per: cellPixelWidth),
          height: cellsFromPixels(targetPixelHeight, per: cellPixelHeight)
        )
      case (let width?, nil):
        guard width > 0 else {
          return .zero
        }
        return CellSize(
          width: width,
          height: max(1, Int((Double(width) / cellAspect).rounded(rounding)))
        )
      case (nil, let height?):
        guard height > 0 else {
          return .zero
        }
        return CellSize(
          width: max(1, Int((Double(height) * cellAspect).rounded(rounding))),
          height: height
        )
      case (nil, nil):
        return intrinsicSize
      }
    }
  }

}
