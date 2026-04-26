/// A precomputed message authentication key, which can be used to compute
/// hash-based message authentication codes ([HMACs](https://en.wikipedia.org/wiki/HMAC)).
///
/// Using this type to generate authentication codes for many messages with
/// the same base key is faster than repeatedly calling
/// ``MessageAuthenticationHash.init(authenticating:key:)``.
@frozen public
struct MessageAuthenticationKey<Hash> where Hash:MessageAuthenticationHash
{
    public
    let inner:[UInt8]
    public
    let outer:[UInt8]

    /// Creates a message authentication key from the given base key.
    @inlinable public
    init(_ key:some Collection<UInt8>)
    {
        let normalized:[UInt8]
        let count:Int = key.count
        if      count > Hash.stride
        {
            let key:Hash = .init(hashing: key)
            normalized = [UInt8].init(key) + repeatElement(0, count: Hash.stride - Hash.count)
        }
        else if count < Hash.stride
        {
            normalized = [UInt8].init(key) + repeatElement(0, count: Hash.stride - count)
        }
        else
        {
            normalized = [UInt8].init(key)
        }

        self.inner = normalized.map { $0 ^ 0x36 }
        self.outer = normalized.map { $0 ^ 0x5c }
    }
}
extension MessageAuthenticationKey
{
    /// Computes a hash-based message authentication code
    /// ([HMAC](https://en.wikipedia.org/wiki/HMAC)) for the given message
    /// using this key.
    @inlinable public
    func authenticate(_ message:some Sequence<UInt8>) -> Hash
    {
        .init(hashing: outer + Hash.init(hashing: inner + message))
    }
    /// Derives an encryption key using this message authentication key and
    /// the given salt. If this message authentication key was computed from
    /// a password, then this functions as a password-based key derivation
    /// function ([PBKDR2](https://en.wikipedia.org/wiki/PBKDF2)).
    @inlinable public
    func derive(salt:some Collection<UInt8>, iterations:Int, blocks:Int = 1) -> [UInt8]
    {
        var output:[UInt8] = []
            output.reserveCapacity(blocks * Hash.count)
        for block:UInt32 in 1 ... UInt32.init(blocks)
        {
            let salt:[UInt8] = withUnsafeBytes(of: block.bigEndian) { [UInt8].init(salt) + $0 }

            var hash:Hash = self.authenticate(salt)
            var block:[UInt8] = .init(hash)

            for _ in 1 ..< iterations
            {
                hash = self.authenticate(hash)
                for (index, byte):(Int, UInt8) in zip(block.indices, hash)
                {
                    block[index] ^= byte
                }
            }

            output.append(contentsOf: block)
        }
        return output
    }
}
