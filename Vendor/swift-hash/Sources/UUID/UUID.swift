import Base16

@frozen public
struct UUID:Sendable
{
    /// The raw bit pattern of this UUID.
    ///
    /// UUIDs are always big-endian, regardless of platform endianness, so the first
    /// tuple element contains the high 64 bits of the UUID, and the second tuple
    /// element contains the low 64 bits.
    ///
    /// The constituent ``UInt64`` components are also big-endian, and so their
    /// numeric value, as interpreted by the current host, may vary among host
    /// machines. In particular, do *not* assume that the *n*-th bit in the *i*th
    /// component corresponds to a fixed bit in the UUID.
    public
    let bitPattern:(UInt64, UInt64)

    /// Creates a UUID with the given bit pattern. Do not use this initializer
    /// to create a UUID from integer literals; use ``init(_:_:)``, which accounts
    /// for platform endianness, instead.
    @inlinable public
    init(bitPattern:(UInt64, UInt64))
    {
        self.bitPattern = bitPattern
    }

    /// Creates a UUID with the given high- and low-components. The components
    /// are interpreted by platform endianness; therefore the values stored
    /// into ``bitPattern`` may be different if the current host is not big-endian.
    @inlinable public
    init(_ high:UInt64, _ low:UInt64)
    {
        self.init(bitPattern: (high.bigEndian, low.bigEndian))
    }
}
extension UUID
{
    /// Generates an [RFC 4122](https://www.rfc-editor.org/rfc/rfc4122)-compliant
    /// random UUID (version 4).
    @inlinable public
    static func random() -> Self
    {
        var bitPattern:(UInt64, UInt64) =
        (
            .random(in: .min ... .max),
            .random(in: .min ... .max)
        )
        withUnsafeMutableBytes(of: &bitPattern)
        {
            $0[6] = 0b0100_0000 |
                    0b0000_1111 & $0[6]
            $0[8] = 0b1000_0000 |
                    0b0011_1111 & $0[8]
        }
        return .init(bitPattern: bitPattern)
    }
    /// Creates a UUID by initializing its raw memory from a collection of bytes.
    /// If the collection does not contain at least 16 bytes, the uninitalized
    /// portion of the UUID is filled with zero bytes.
    @inlinable public
    init<Bytes>(_ bytes:Bytes) where Bytes:Collection, Bytes.Element == UInt8
    {
        self.init(bitPattern: (0, 0))
        withUnsafeMutableBytes(of: &self)
        {
            assert($0.count == 16)
            $0.copyBytes(from: bytes)
        }
    }
}
extension UUID:Equatable
{
    @inlinable public
    static func == (a:Self, b:Self) -> Bool { a.bitPattern == b.bitPattern }
}
extension UUID:Hashable
{
    @inlinable public
    func hash(into hasher:inout Hasher)
    {
        // do not use the ``UInt64`` components directly, their numeric
        // values may differ by endianness
        for byte:UInt8 in self
        {
            byte.hash(into: &hasher)
        }
    }
}
extension UUID:RandomAccessCollection
{
    @inlinable public
    var startIndex:Int
    {
        0
    }
    @inlinable public
    var endIndex:Int
    {
        16
    }
    @inlinable public
    subscript(index:Int) -> UInt8
    {
        precondition(self.indices ~= index)
        return withUnsafeBytes(of: self) { $0[index] }
    }
}
extension UUID:LosslessStringConvertible
{
    @inlinable public
    init?(_ string:String)
    {
        // do this instead of decoding directly into raw memory so we can check
        // that the byte count is exactly 16
        let bytes:[UInt8] = Base16.decode(string)
        if  bytes.count == 16
        {
            self.init(bytes)
        }
        else
        {
            return nil
        }
    }
    public
    var description:String
    {
        """
        \(Base16.encode(self[ 0 ..<  4], with: Base16.LowercaseDigits.self))-\
        \(Base16.encode(self[ 4 ..<  6], with: Base16.LowercaseDigits.self))-\
        \(Base16.encode(self[ 6 ..<  8], with: Base16.LowercaseDigits.self))-\
        \(Base16.encode(self[ 8 ..< 10], with: Base16.LowercaseDigits.self))-\
        \(Base16.encode(self[10 ..< 16], with: Base16.LowercaseDigits.self))
        """
    }
}
