extension Base64
{
    /// An abstraction over text input, which discards characters that are not valid base-64
    /// digits. It handles the core Base64 character set, as well as the URL-safe variant.
    ///
    /// Iteration over an instance of this type will halt upon encountering the first `'='`
    /// padding character, even if the underlying sequence contains more characters.
    @frozen @usableFromInline
    struct Values<ASCII> where ASCII:Sequence<UInt8>
    {
        @usableFromInline
        var iterator:ASCII.Iterator

        @inlinable
        init(_ ascii:ASCII)
        {
            self.iterator = ascii.makeIterator()
        }
    }
}
extension Base64.Values:Sequence, IteratorProtocol
{
    @usableFromInline
    typealias Iterator = Self

    @inlinable mutating
    func next() -> UInt8?
    {
        while let digit:UInt8 = self.iterator.next(), digit != 0x3D // '='
        {
            switch digit
            {
            case 0x41 ... 0x5a: // A-Z
                return digit - 0x41
            case 0x61 ... 0x7a: // a-z
                return digit - 0x61 + 26
            case 0x30 ... 0x39: // 0-9
                return digit - 0x30 + 52
            case 0x2b, 0x2d: // +, -
                return 62
            case 0x2f, 0x5f: // /, _
                return 63
            default:
                continue
            }
        }
        return nil
    }
}
