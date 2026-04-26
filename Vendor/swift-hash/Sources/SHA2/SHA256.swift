import Base16
import MessageAuthentication

@frozen public
struct SHA256:Sendable
{
    public
    typealias Words = (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)

    public static
    let table:[UInt32] =
    [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public
    var words:Words

    @inlinable public
    init(words:Words =
    (
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19
    ))
    {
        self.words = words
    }

    @inlinable public
    init<Message>(hashing message:Message) where Message:Collection<UInt8>
    {
        self.init()

        var blocks:Int = 0
        var start:Message.Index = message.startIndex
        while let end:Message.Index =
            message.index(start, offsetBy: 64, limitedBy: message.endIndex)
        {
            self.update(with: message[start ..< end])
            blocks += 1
            start = end
        }

        var epilogue:[UInt8] = []
        epilogue.reserveCapacity(128)
        epilogue.append(contentsOf: message[start...])

        let remaining:Int = epilogue.count
        // 1 byte separator + 8 bytes UInt64 + however many more it takes to
        // get to a multiple of 64
        let padding:Int = (119 - remaining) & 63
        let count:Int = blocks << 6 | remaining

        epilogue.append(0x80)
        epilogue.append(contentsOf: repeatElement(0x00, count: padding))
        withUnsafeBytes(of: UInt64.init(count << 3).bigEndian)
        {
            epilogue.append(contentsOf: $0)
        }
        if epilogue.count == 128
        {
            self.update(with: epilogue[..<64])
            self.update(with: epilogue[64...])
        }
        else
        {
            self.update(with: epilogue)
        }
    }

    @inlinable public mutating
    func update<Chunk>(with chunk:Chunk) where Chunk:Collection<UInt8>
    {
        assert(chunk.count == 64)

        let schedule:[UInt32] = .init(unsafeUninitializedCapacity: 64)
        {
            (buffer:inout UnsafeMutableBufferPointer<UInt32>, count:inout Int) in

            count = 64

            var base:Chunk.Index = chunk.startIndex
            for i:Int in 0 ..< 16
            {
                // big-endian
                let c:Chunk.Index = chunk.index(after: base)
                let b:Chunk.Index = chunk.index(after: c)
                let a:Chunk.Index = chunk.index(after: b)
                buffer[i] =
                    UInt32.init(chunk[base])    << 24 |
                    UInt32.init(chunk[c])       << 16 |
                    UInt32.init(chunk[b])       <<  8 |
                    UInt32.init(chunk[a])
                base = chunk.index(after: a)
            }
            for i:Int in 16 ..< count
            {
                let s:(UInt32, UInt32)
                s.0             =   Self.rotate(buffer[i - 15], right:  7) ^
                                    Self.rotate(buffer[i - 15], right: 18) ^
                                    (buffer[i - 15] >>  3 as UInt32)
                s.1             =   Self.rotate(buffer[i -  2], right: 17) ^
                                    Self.rotate(buffer[i -  2], right: 19) ^
                                    (buffer[i -  2] >> 10 as UInt32)
                let t:UInt32    =   s.0 &+ s.1
                buffer[i]       = buffer[i - 16] &+ buffer[i - 7] &+ t
            }
        }

        var (a, b, c, d, e, f, g, h):Words = self.words

        for i:Int in 0 ..< 64
        {
            let s:(UInt32, UInt32)
            s.1     =   Self.rotate(e, right:  6) ^
                        Self.rotate(e, right: 11) ^
                        Self.rotate(e, right: 25)
            s.0     =   Self.rotate(a, right:  2) ^
                        Self.rotate(a, right: 13) ^
                        Self.rotate(a, right: 22)
            let ch:UInt32   = (e & f) ^ (~e & g)
            let temp:(UInt32, UInt32)
            temp.0          = h &+ s.1 &+ ch &+ Self.table[i] &+ schedule[i]
            let maj:UInt32  = (a & b) ^ (a & c) ^ (b & c)
            temp.1          = maj &+ s.0

            h = g
            g = f
            f = e
            e = d &+ temp.0
            d = c
            c = b
            b = a
            a = temp.0 &+ temp.1
        }

        self.words.0 &+= a
        self.words.1 &+= b
        self.words.2 &+= c
        self.words.3 &+= d
        self.words.4 &+= e
        self.words.5 &+= f
        self.words.6 &+= g
        self.words.7 &+= h
    }

    @inlinable public static
    func rotate(_ value:UInt32, right shift:Int) -> UInt32
    {
        (value >> shift) | (value << (UInt32.bitWidth - shift))
    }
}

extension SHA256:Equatable
{
    @inlinable public static
    func == (lhs:Self, rhs:Self) -> Bool
    {
        lhs.words.0 == rhs.words.0 &&
        lhs.words.1 == rhs.words.1 &&
        lhs.words.2 == rhs.words.2 &&
        lhs.words.3 == rhs.words.3 &&
        lhs.words.4 == rhs.words.4 &&
        lhs.words.5 == rhs.words.5 &&
        lhs.words.6 == rhs.words.6 &&
        lhs.words.7 == rhs.words.7
    }
}
extension SHA256:Hashable
{
    @inlinable public
    func hash(into hasher:inout Hasher)
    {
        self.words.0.hash(into: &hasher)
        self.words.1.hash(into: &hasher)
        self.words.2.hash(into: &hasher)
        self.words.3.hash(into: &hasher)
        self.words.4.hash(into: &hasher)
        self.words.5.hash(into: &hasher)
        self.words.6.hash(into: &hasher)
        self.words.7.hash(into: &hasher)
    }
}
extension SHA256:MessageAuthenticationHash
{
    public static
    let stride:Int = 64
    public static
    let count:Int = 32

    @inlinable public
    var startIndex:Int
    {
        0
    }
    @inlinable public
    subscript(index:Int) -> UInt8
    {
        withUnsafePointer(to: self.words)
        {
            $0.withMemoryRebound(to: UInt32.self, capacity: 8)
            {
                // big-endian
                UInt8.init(($0[index >> 2] << ((index & 3) << 3)) >> 24)
            }
        }
    }
}

extension SHA256:ExpressibleByStringLiteral
{
    @inlinable public
    init?(parsing ascii:some Sequence<UInt8>)
    {
        guard let words:Words = Base16.decode(ascii, loading: Words.self)
        else
        {
            return nil
        }

        self.init(words:
        (
            .init(bigEndian: words.0),
            .init(bigEndian: words.1),
            .init(bigEndian: words.2),
            .init(bigEndian: words.3),
            .init(bigEndian: words.4),
            .init(bigEndian: words.5),
            .init(bigEndian: words.6),
            .init(bigEndian: words.7)
        ))
    }

    @inlinable public
    init(stringLiteral:String)
    {
        if let hash:Self = Self.init(parsing: stringLiteral.utf8)
        {
            self = hash
        }
        else
        {
            fatalError("invalid hex literal '\(stringLiteral)'")
        }
    }
}
extension SHA256:CustomStringConvertible
{
    @inlinable public
    var description:String
    {
        Base16.encode(storing:
        (
            self.words.0.bigEndian,
            self.words.1.bigEndian,
            self.words.2.bigEndian,
            self.words.3.bigEndian,
            self.words.4.bigEndian,
            self.words.5.bigEndian,
            self.words.6.bigEndian,
            self.words.7.bigEndian
        ),
        with: Base16.LowercaseDigits.self)
    }
}
