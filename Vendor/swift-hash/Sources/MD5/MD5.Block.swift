extension MD5
{
    @frozen public
    struct Block
    {
        public
        typealias Words =
        (
            UInt32, UInt32, UInt32, UInt32,
            UInt32, UInt32, UInt32, UInt32,
            UInt32, UInt32, UInt32, UInt32,
            UInt32, UInt32, UInt32, UInt32
        )

        public
        var words:Words

        @inlinable
        init(words:Words = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        {
            self.words = words
        }
    }
}
extension MD5.Block
{
    @inlinable
    subscript(word:Int) -> UInt32
    {
        get
        {
            withUnsafeBytes(of: self.words)
            {
                $0.bindMemory(to: UInt32.self)[word]
            }
        }
        set(value)
        {
            withUnsafeMutableBytes(of: &self.words)
            {
                $0.bindMemory(to: UInt32.self)[word] = value
            }
        }
    }
}
extension MD5.Block
{
    @inlinable static
    func copy(from bytes:some Collection<UInt8>) -> Self
    {
        withUnsafeTemporaryAllocation(
            byteCount: MemoryLayout<Words>.size,
            alignment: MemoryLayout<Words>.alignment)
        {
            $0.copyBytes(from: bytes)

            var block:Self = .init(words: $0.load(as: Words.self))
            for i:Int in 0 ..< 16
            {
                block[i] = .init(littleEndian: block[i])
            }
            return block
        }
    }
    @inlinable static
    func copy(last bytes:some Collection<UInt8>, length:Int) -> (Self, Self?)
    {
        //  Zero-initialize
        var first:Self = .init()
        var count:Int = 0

        withUnsafeMutableBytes(of: &first.words)
        {
            for byte:UInt8 in bytes
            {
                $0[count] = byte
                count += 1
            }

            $0[count] = 0x80
        }

        for i:Int in 0 ..< 16
        {
            first[i] = .init(littleEndian: first[i])
        }

        let bits:UInt = .init(length * 8)
        if  count < 56
        {
            first[14] = UInt32.init(bits & 0xFFFF_FFFF)
            first[15] = UInt32.init(bits >> 32)

            return (first, nil)
        }
        else
        {
            var second:Self = .init()
            second[14] = UInt32.init(bits & 0xFFFF_FFFF)
            second[15] = UInt32.init(bits >> 32)

            return (first, second)
        }
    }
}
