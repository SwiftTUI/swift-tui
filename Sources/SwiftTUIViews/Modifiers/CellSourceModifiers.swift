extension View {
  /// Adjusts the ink, paper or coverage of each glyph drawn by the subject.
  public func colorEffect(_ shader: CellColorShader, isEnabled: Bool = true) -> some View {
    layerEffect(shader.layer, maxSampleOffset: .zero, isEnabled: isEnabled)
  }

  /// Adjusts each painted glyph with an inline color program.
  public func colorEffect(isEnabled: Bool = true, _ shade: @escaping CellColorShader.Function)
    -> some View
  {
    colorEffect(CellColorShader(shade), isEnabled: isEnabled)
  }

  /// Samples the subject at the source position returned by a mapping.
  public func distortionEffect(
    _ shader: CellDistortionShader, maxSampleOffset: CellSampleOffset, isEnabled: Bool = true
  ) -> some View {
    layerEffect(shader.layer, maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
  }

  /// Maps each output position to a source-local position with a Swift function.
  public func distortionEffect(
    maxSampleOffset: CellSampleOffset, isEnabled: Bool = true,
    _ map: @escaping CellDistortionShader.Function
  ) -> some View {
    distortionEffect(
      CellDistortionShader(map), maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
  }
}
