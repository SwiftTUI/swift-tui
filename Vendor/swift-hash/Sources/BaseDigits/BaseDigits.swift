public
protocol BaseDigits
{
    /// Gets the ASCII value for the given remainder.
    static
    subscript(remainder:UInt8) -> UInt8 { get }
}
extension BaseDigits
{
    /// Gets the ASCII value for the given remainder as a ``Unicode.Scalar``.
    @inlinable public static
    subscript(remainder:UInt8, as _:Unicode.Scalar.Type = Unicode.Scalar.self) -> Unicode.Scalar
    {
        .init(Self[remainder])
    }
    /// Gets the ASCII value for the given remainder as a ``Character``.
    @inlinable public static
    subscript(remainder:UInt8, as _:Character.Type = Character.self) -> Character
    {
        .init(Self[remainder, as: Unicode.Scalar.self])
    }
}
