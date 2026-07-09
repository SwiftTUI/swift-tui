extension ResolvedTextStyle {
  public func composited(
    over underlay: ResolvedTextStyle?
  ) -> ResolvedTextStyle {
    composited(over: underlay, blendMode: nil)
  }

  internal func composited(
    over underlay: ResolvedTextStyle?,
    blendMode: BlendMode?
  ) -> ResolvedTextStyle {
    guard let underlay else {
      return self
    }

    let blendedBackground: Color? =
      if let blendMode {
        compositedColor(
          source: backgroundColor,
          over: underlay.backgroundColor,
          blendMode: blendMode
        )
      } else {
        switch (backgroundColor, underlay.backgroundColor) {
        case (let overlay?, let under?) where overlay.alpha < 1:
          under.mixed(
            with: Color(red: overlay.red, green: overlay.green, blue: overlay.blue),
            amount: overlay.alpha)
        case (let overlay?, _):
          overlay
        case (nil, let under?):
          under
        case (nil, nil):
          Color?.none
        }
      }

    return .init(
      foregroundColor: compositedColor(
        source: foregroundColor,
        over: underlay.foregroundColor,
        blendMode: blendMode
      ),
      backgroundColor: blendedBackground,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  private func compositedColor(
    source: Color?,
    over backdrop: Color?,
    blendMode: BlendMode?
  ) -> Color? {
    guard let source else {
      return backdrop
    }
    guard let blendMode, let backdrop else {
      return source
    }
    return source.composited(over: backdrop, mode: blendMode)
  }

  public func tinted(with overlay: Color) -> ResolvedTextStyle {
    let amount = overlay.alpha
    guard amount > 0 else {
      return self
    }
    let opaque = Color(
      red: overlay.red,
      green: overlay.green,
      blue: overlay.blue,
      profile: overlay.profile
    )
    return .init(
      foregroundColor: foregroundColor.map { $0.mixed(with: opaque, amount: amount) },
      backgroundColor: backgroundColor.map { $0.mixed(with: opaque, amount: amount) } ?? overlay,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle,
      opacity: opacity
    )
  }

  public init(
    _ style: TextStyle,
    theme: Theme = .default
  ) {
    self.init(
      foregroundColor: style.foregroundStyle.flatMap {
        resolveStyleColor(style: $0, theme: theme)
      },
      backgroundColor: style.backgroundStyle.flatMap {
        resolveStyleColor(style: $0, theme: theme)
      },
      emphasis: style.emphasis,
      underlineStyle: style.underlineStyle,
      strikethroughStyle: style.strikethroughStyle,
      opacity: style.opacity
    )
  }
}
