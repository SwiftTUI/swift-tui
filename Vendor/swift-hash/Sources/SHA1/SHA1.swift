/// The value of a [SHA-1](https://en.wikipedia.org/wiki/SHA-1) hash.
///
/// Currently this type can only represent a SHA-1 hash value; it cannot yet compute the hash.
@frozen public
struct SHA1:Equatable, Hashable, Sendable
{
    @usableFromInline
    typealias Storage = (UInt32, UInt32, UInt32, UInt32, UInt32)

    @usableFromInline
    var buffer:InlineBuffer<Storage>

    @inlinable
    init(buffer:InlineBuffer<Storage>)
    {
        self.buffer = buffer
    }
}
extension SHA1
{
    @inlinable public static
    func copy(from bytes:some RandomAccessCollection<UInt8>) -> Self?
    {
        InlineBuffer<Storage>.copy(from: bytes).map(Self.init(buffer:))
    }
}
extension SHA1:Comparable
{
    /// Compares two SHA1 hashes in the order they would sort if they were printed as base-16
    /// strings with consistent casing. (This function does not actually convert the hashes to
    /// strings.)
    @inlinable public static
    func < (lhs:Self, rhs:Self) -> Bool
    {
        lhs.buffer < rhs.buffer
    }
}
extension SHA1:RandomAccessCollection, MutableCollection
{
    @inlinable public
    var startIndex:Int { self.buffer.startIndex }

    @inlinable public
    var endIndex:Int { self.buffer.endIndex }

    @inlinable public
    subscript(index:Int) -> UInt8
    {
        get         { self.buffer[index] }
        set(value)  { self.buffer[index] = value }
    }
}
extension SHA1:CustomStringConvertible
{
    @inlinable public
    var description:String { self.buffer.description }
}
extension SHA1:LosslessStringConvertible
{
    @inlinable public
    init?(_ description:borrowing String)
    {
        if  let buffer:InlineBuffer<Storage> = .init(description)
        {
            self.init(buffer: buffer)
        }
        else
        {
            return nil
        }
    }

    @inlinable public
    init?(_ description:borrowing Substring)
    {
        if  let buffer:InlineBuffer<Storage> = .init(description)
        {
            self.init(buffer: buffer)
        }
        else
        {
            return nil
        }
    }
}
@available(macOS 13.3, iOS 16.4, macCatalyst 16.4, tvOS 16.4, visionOS 1, watchOS 9.4, *)
extension SHA1:ExpressibleByIntegerLiteral
{
    @inlinable public
    init(integerLiteral:StaticBigInt)
    {
        self.init(buffer: .init(integerLiteral: integerLiteral))
    }
}
extension SHA1
{
    @available(*, unavailable, message: "unimplemented")
    @inlinable public
    init(hashing message:__shared some Collection<UInt8>)
    {
        fatalError()
    }
}
