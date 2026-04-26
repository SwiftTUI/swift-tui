@frozen public
struct InlineBuffer<Storage>:Sendable where Storage:Sendable
{
    public
    var storage:Storage

    @inlinable public
    init(storage:Storage)
    {
        self.storage = storage
    }
}
extension InlineBuffer
{
    /// Load an instance of this buffer type from little-endian binary data. Returns nil if the
    /// input does not contain exactly `MemoryLayout<Storage>.size` bytes.
    @inlinable public static
    func copy(from bytes:some RandomAccessCollection<UInt8>) -> Self?
    {
        if  bytes.count == MemoryLayout<Storage>.size
        {
            let storage:Storage = withUnsafeTemporaryAllocation(
                byteCount: MemoryLayout<Storage>.size,
                alignment: MemoryLayout<Storage>.alignment)
            {
                $0.copyBytes(from: bytes)
                return $0.load(as: Storage.self)
            }
            return .init(storage: storage)
        }
        else
        {
            return nil
        }
    }
}
extension InlineBuffer:Equatable
{
    @inlinable public static
    func == (lhs:Self, rhs:Self) -> Bool
    {
        withUnsafeBytes(of: lhs.storage)
        {
            (lhs:UnsafeRawBufferPointer) in
            withUnsafeBytes(of: rhs.storage)
            {
                (rhs:UnsafeRawBufferPointer) in
                lhs.elementsEqual(rhs)
            }
        }
    }
}
extension InlineBuffer:Hashable
{
    @inlinable public
    func hash(into hasher:inout Hasher)
    {
        withUnsafeBytes(of: self.storage)
        {
            hasher.combine(bytes: $0)
        }
    }
}
extension InlineBuffer:Comparable
{
    @inlinable public static
    func < (lhs:Self, rhs:Self) -> Bool
    {
        withUnsafeBytes(of: lhs.storage)
        {
            (lhs:UnsafeRawBufferPointer) in
            withUnsafeBytes(of: rhs.storage)
            {
                (rhs:UnsafeRawBufferPointer) in
                lhs.lexicographicallyPrecedes(rhs)
            }
        }
    }
}
extension InlineBuffer:RandomAccessCollection, MutableCollection
{
    @inlinable public
    var startIndex:Int { 0 }

    @inlinable public
    var endIndex:Int { MemoryLayout<Storage>.size }

    @inlinable public
    subscript(index:Int) -> UInt8
    {
        get
        {
            precondition(self.indices ~= index, "index out of range")
            return withUnsafeBytes(of:  self.storage) { $0[index] }
        }
        set(value)
        {
            precondition(self.indices ~= index, "index out of range")
            withUnsafeMutableBytes(of: &self.storage) { $0[index] = value }
        }
    }
}
@available(macOS 13.3, iOS 16.4, macCatalyst 16.4, tvOS 16.4, visionOS 1, watchOS 9.4, *)
extension InlineBuffer:ExpressibleByIntegerLiteral
{
    @inlinable public
    init(integerLiteral:__shared StaticBigInt)
    {
        precondition(integerLiteral.signum() >= 0, """
            inline buffer literal cannot be negative
            """)
        // +1 bit for “sign” bit
        precondition(integerLiteral.bitWidth <= MemoryLayout<Storage>.size * 8 + 1, """
            inline buffer literal overflows UInt\(MemoryLayout<Storage>.size * 8) \
            (bit width: \(integerLiteral.bitWidth))
            """)

        let storage:Storage = withUnsafeTemporaryAllocation(
                byteCount: MemoryLayout<Storage>.size,
                alignment: MemoryLayout<Storage>.alignment)
        {
            (self:UnsafeMutableRawBufferPointer) in

            var i:Int = MemoryLayout<Storage>.size
            for w:Int in 0...
            {
                withUnsafeBytes(of: integerLiteral[w].littleEndian)
                {
                    for value:UInt8 in $0
                    {
                        i = self.index(before: i)
                        self[i] = value
                        if  i == 0
                        {
                            return
                        }
                    }
                }
                if  i == 0
                {
                    break
                }
            }
            return self.load(as: Storage.self)
        }

        self.init(storage: storage)
    }
}
extension InlineBuffer:CustomStringConvertible
{
    /// Prints the bytes of this inline buffer in the order they appear in memory. The first
    /// pair of hex digits in the returned string represent the first byte in this buffer.
    @inlinable public
    var description:String
    {
        func hex(remainder:UInt8) -> UInt8
        {
            (remainder < 10 ? 0x30 : 0x61 - 10) &+ remainder
        }
        if #available(macOS 11, iOS 14, macCatalyst 14, tvOS 14, visionOS 1, watchOS 7, *)
        {
            return .init(unsafeUninitializedCapacity: 2 * self.count)
            {
                for (i, byte):(Int, UInt8) in self.enumerated()
                {
                    $0[2 * i    ] = hex(remainder: byte >> 4)
                    $0[2 * i + 1] = hex(remainder: byte & 0x0f)
                }
                return 2 * self.count
            }
        }
        else
        {
            var description:String = ""
            description.reserveCapacity(2 * self.count)
            for byte:UInt8 in self
            {
                description.append(Character.init(.init(hex(remainder: byte >> 4))))
                description.append(Character.init(.init(hex(remainder: byte & 0x0f))))
            }
            return description
        }
    }
}
extension InlineBuffer:LosslessStringConvertible
{
    /// Parses a string of hexadecimal digits into an inline buffer. Returns nil if the input
    /// string does not contain exactly `MemoryLayout<Storage>.size * 2` ASCII hex digits.
    /// The input string must not begin with `0x`, or contain any non-digit characters at all.
    @inlinable public
    init?<String>(_ description:__shared String) where String:StringProtocol
    {
        let storage:Storage? = withUnsafeTemporaryAllocation(
            byteCount: MemoryLayout<Storage>.size,
            alignment: MemoryLayout<Storage>.alignment)
        {
            func remainder(hex:UInt8) -> UInt8?
            {
                switch hex
                {
                case 0x30 ... 0x39: hex      - 0x30
                case 0x61 ... 0x66: hex + 10 - 0x61
                case 0x41 ... 0x46: hex + 10 - 0x41
                default:            nil
                }
            }

            var input:String.UTF8View.Iterator = description.utf8.makeIterator()
            for i:Int in 0 ..< MemoryLayout<Storage>.size
            {
                if  case let high?? = input.next().map(remainder(hex:)),
                    case let low?? = input.next().map(remainder(hex:))
                {
                    $0[i] = .init(high << 4 | low)
                }
                else
                {
                    return nil
                }
            }
            guard case nil = input.next()
            else
            {
                return nil
            }

            return $0.load(as: Storage.self)
        }
        if  let storage:Storage
        {
            self.init(storage: storage)
        }
        else
        {
            return nil
        }
    }
}
