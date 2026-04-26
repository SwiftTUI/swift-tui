@frozen public
struct MD5:Equatable, Hashable, Sendable
{
    @usableFromInline
    typealias Storage = (UInt32, UInt32, UInt32, UInt32)

    @usableFromInline
    var buffer:InlineBuffer<Storage>

    @inlinable
    init(buffer:InlineBuffer<Storage>)
    {
        self.buffer = buffer
    }
}
extension MD5
{
    @inlinable public static
    func copy(from bytes:some RandomAccessCollection<UInt8>) -> Self?
    {
        InlineBuffer<Storage>.copy(from: bytes).map(Self.init(buffer:))
    }
}
extension MD5
{
    @inlinable public
    init(words:Words)
    {
        self.init(buffer: .init(storage: words.littleEndian))
    }
    @inlinable public
    var words:Words
    {
        get
        {
            .init(littleEndian: self.buffer.storage)
        }
        set(value)
        {
            self.buffer.storage = value.littleEndian
        }
    }
}
extension MD5:Comparable
{
    /// Compares two MD5 hashes in the order they would sort if they were printed as base-16
    /// strings with consistent casing. (This function does not actually convert the hashes to
    /// strings.)
    @inlinable public static
    func < (lhs:Self, rhs:Self) -> Bool
    {
        lhs.buffer < rhs.buffer
    }
}
extension MD5:RandomAccessCollection, MutableCollection
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
extension MD5:CustomStringConvertible
{
    public
    var description:String { self.buffer.description }
}
extension MD5:LosslessStringConvertible
{
    public
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

    public
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
extension MD5:ExpressibleByIntegerLiteral
{
    @inlinable public
    init(integerLiteral:borrowing StaticBigInt)
    {
        self.init(buffer: .init(integerLiteral: integerLiteral))
    }
}
extension MD5
{
    @inlinable public
    init<Message>(hashing message:__shared Message) where Message:Collection<UInt8>
    {
        var words:Words = .init()

        var start:Message.Index = message.startIndex
        while   let end:Message.Index = message.index(start,
                    offsetBy: 64,
                    limitedBy: message.endIndex)
        {
            words.update(with: .copy(from: message[start ..< end]))
            start = end
        }
        switch Block.copy(last: message[start...], length: message.count)
        {
        case (let first, nil):
            words.update(with: first)

        case (let first, let second?):
            words.update(with: first)
            words.update(with: second)
        }

        self.init(words: words)
    }
}
