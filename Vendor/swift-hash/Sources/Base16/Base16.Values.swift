extension Base16
{
    /// An abstraction over text input, which discards characters that are not
    /// valid base-16 digits.
    public
    struct Values<ASCII> where ASCII:Sequence<UInt8>
    {
        public
        var iterator:ASCII.Iterator

        @inlinable public
        init(_ ascii:ASCII)
        {
            self.iterator = ascii.makeIterator()
        }
    }
}
extension Base16.Values:Sequence, IteratorProtocol
{
    public
    typealias Iterator = Self

    @inlinable public mutating
    func next() -> UInt8?
    {
        while let digit:UInt8 = self.iterator.next()
        {
            switch digit
            {
            case 0x30 ... 0x39: return digit      - 0x30
            case 0x61 ... 0x66: return digit + 10 - 0x61
            case 0x41 ... 0x46: return digit + 10 - 0x41
            default:            continue
            }
        }
        return nil
    }
}
