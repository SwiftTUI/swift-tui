import BaseDigits

/// A namespace for base-16 utilities.
public
enum Base16
{
    /// Decodes some ``String``-like type containing an ASCII-encoded base-16 string
    /// to some ``RangeReplaceableCollection`` type. The order of the decoded bytes
    /// in the output matches the order of the (pairs of) hexadecimal digits in the
    /// input string.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped. If the string does not contain an even number of digits,
    /// the trailing digit will be ignored.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable public static
    func decode<Bytes>(_ ascii:some StringProtocol, to _:Bytes.Type = Bytes.self) -> Bytes
        where Bytes:RangeReplaceableCollection<UInt8>
    {
        self.decode(ascii.utf8, to: Bytes.self)
    }
    /// Decodes an ASCII-encoded base-16 string to some ``RangeReplaceableCollection`` type.
    /// The order of the decoded bytes in the output matches the order of the (pairs of)
    /// hexadecimal digits in the input.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped. If the input does not yield an even number of digits, the
    /// trailing digit will be ignored.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable public static
    func decode<ASCII, Bytes>(_ ascii:ASCII, to _:Bytes.Type = Bytes.self) -> Bytes
        where Bytes:RangeReplaceableCollection<UInt8>, ASCII:Sequence<UInt8>
    {
        var bytes:Bytes = .init()
            bytes.reserveCapacity(ascii.underestimatedCount / 2)
        var values:Values<ASCII> = .init(ascii)
        while   let high:UInt8 = values.next(),
                let low:UInt8 = values.next()
        {
            bytes.append(high << 4 | low)
        }
        return bytes
    }
    /// Encodes a sequence of bytes to a base-16 string with the specified lettercasing.
    @inlinable public static
    func encode<Digits>(_ bytes:some Sequence<UInt8>, with _:Digits.Type) -> String
        where Digits:BaseDigits
    {
        var encoded:String = ""
            encoded.reserveCapacity(bytes.underestimatedCount * 2)
        for byte:UInt8 in bytes
        {
            encoded.append(Digits[byte >> 4])
            encoded.append(Digits[byte & 0x0f])
        }
        return encoded
    }
}
extension Base16
{
    /// Decodes an ASCII-encoded base-16 string into a pre-allocated buffer,
    /// returning `nil` if the input did not yield enough digits to fill
    /// the buffer completely.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-16 digits
    /// will be skipped.
    @inlinable public static
    func decode<ASCII>(_ ascii:ASCII, into bytes:UnsafeMutableRawBufferPointer) -> Void?
        where ASCII:Sequence<UInt8>
    {
        var values:Values<ASCII> = .init(ascii)
        for offset:Int in bytes.indices
        {
            if  let high:UInt8 = values.next(),
                let low:UInt8 = values.next()
            {
                bytes[offset] = high << 4 | low
            }
            else
            {
                return nil
            }
        }
        return ()
    }
    /// Encodes a sequence of bytes into a pre-allocated buffer as a base-16
    /// string with the specified lettercasing.
    ///
    /// The size of the `ascii` buffer must be exactly twice the inline size
    /// of `words`. If this method is used incorrectly, the output buffer may
    /// be incompletely initialized, but it will never write to memory outside
    /// of the buffer’s bounds.
    @inlinable public static
    func encode<BigEndian, Digits>(storing words:BigEndian,
        into ascii:UnsafeMutableRawBufferPointer,
        with _:Digits.Type)
        where Digits:BaseDigits
    {
        withUnsafeBytes(of: words)
        {
            assert(2 * $0.count <= ascii.count)

            for (offset, byte):(Int, UInt8)
                in zip(stride(from: ascii.startIndex, to: ascii.endIndex, by: 2), $0)
            {
                ascii[offset    ] = Digits[byte >> 4]
                ascii[offset + 1] = Digits[byte & 0x0f]
            }
        }
    }
}
extension Base16
{
    /// Decodes an ASCII-encoded base-16 string to some (usually trivial) type.
    /// This is essentially the same as loading values from raw memory, so this
    /// method should only be used to load trivial types.
    @inlinable public static
    func decode<BigEndian>(_ ascii:some Sequence<UInt8>,
        loading _:BigEndian.Type = BigEndian.self) -> BigEndian?
    {
        withUnsafeTemporaryAllocation(
            byteCount: MemoryLayout<BigEndian>.size,
            alignment: MemoryLayout<BigEndian>.alignment)
        {
            let words:UnsafeMutableRawBufferPointer = $0
            if case _? = Self.decode(ascii, into: words)
            {
                return $0.load(as: BigEndian.self)
            }
            else
            {
                return nil
            }
        }
    }

    /// Encodes the raw bytes of the given value to a base-16 string with the
    /// specified lettercasing. The bytes with the lowest addresses appear first
    /// in the encoded output.
    ///
    /// This method is slightly faster than calling ``encode(_:with:)`` on an
    /// unsafe buffer-pointer view of `words`.
    @inlinable public static
    func encode<BigEndian, Digits>(storing words:BigEndian,
        with _:Digits.Type) -> String
        where Digits:BaseDigits
    {
        let bytes:Int = 2 * MemoryLayout<BigEndian>.size

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
        {
            return .init(unsafeUninitializedCapacity: bytes)
            {
                Self.encode(storing: words,
                    into: UnsafeMutableRawBufferPointer.init($0),
                    with: Digits.self)
                return bytes
            }
        }
        #endif

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        return .init(
            decoding: [UInt8].init(unsafeUninitializedCapacity: bytes)
            {
                Self.encode(storing: words,
                    into: UnsafeMutableRawBufferPointer.init($0),
                    with: Digits.self)
                $1 = bytes
            },
            as: Unicode.UTF8.self)
        #else
        return .init(unsafeUninitializedCapacity: bytes)
        {
            Self.encode(storing: words,
                into: UnsafeMutableRawBufferPointer.init($0),
                with: Digits.self)
            return bytes
        }
        #endif
    }
}
