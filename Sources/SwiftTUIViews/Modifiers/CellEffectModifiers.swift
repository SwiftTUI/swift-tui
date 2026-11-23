extension View {
  /// Transforms cells painted by this mounted view at its position in the draw order.
  public func layerEffect(
    _ shader: CellLayerShader, maxSampleOffset: CellSampleOffset, isEnabled: Bool = true
  ) -> some View {
    modifier(
      DrawEffectModifier(
        effect: isEnabled ? .cellLayer(.init(shader, offset: maxSampleOffset)) : nil))
  }

  /// Transforms cells using a Swift function. Captured inputs must remain stable during paint.
  public func layerEffect(
    maxSampleOffset: CellSampleOffset, isEnabled: Bool = true,
    _ shade: @escaping CellLayerShader.Function
  ) -> some View {
    layerEffect(CellLayerShader(shade), maxSampleOffset: maxSampleOffset, isEnabled: isEnabled)
  }
}
