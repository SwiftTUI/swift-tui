import Base16

/// The value of a [CRC32](https://en.wikipedia.org/wiki/Cyclic_redundancy_check) checksum.
@frozen public
struct CRC32:Hashable, Sendable
{
    @_documentation(visibility: internal)
    public static
    let table:[UInt32] = (0 ..< 256).map
    {
        (i:UInt32) in
        (0 ..< 8).reduce(i){ (c, _) in (c & 1 * 0xed_b8_83_20) ^ c >> 1 }
    }

    /// The checksum value as a 32-bit unsigned integer.
    public
    var checksum:UInt32

    /// Creates a new checksum with the specified value.
    @inlinable public
    init(checksum:UInt32 = 0)
    {
        self.checksum = checksum
    }

    /// Computes the checksum of the provided message.
    @inlinable public
    init(hashing message:borrowing some Sequence<UInt8>)
    {
        self.init()
        self.update(with: message)
    }

    /// Returns a new checksum by hashing the provided message into the current checksum.
    @inlinable public
    func updated(with message:borrowing some Sequence<UInt8>) -> Self
    {
        var checksum:Self = self
        checksum.update(with: message)
        return checksum
    }

    /// Updates the checksum by hashing the provided message into the existing checksum.
    @inlinable public mutating
    func update(with message:borrowing some Sequence<UInt8>)
    {
        self.checksum = ~message.reduce(~self.checksum)
        {
            (state:UInt32, byte:UInt8) in
            Self.table[Int.init(UInt8.init(truncatingIfNeeded: state) ^ byte)] ^ state >> 8
        }
    }
}
extension CRC32:ExpressibleByIntegerLiteral
{
    @inlinable public
    init(integerLiteral:UInt32)
    {
        self.init(checksum: integerLiteral)
    }
}
extension CRC32:CustomStringConvertible
{
    /// The lowercased hexadecimal representation of the checksum value.
    @inlinable public
    var description:String
    {
        Base16.encode(storing: self.checksum.bigEndian, with: Base16.LowercaseDigits.self)
    }
}
