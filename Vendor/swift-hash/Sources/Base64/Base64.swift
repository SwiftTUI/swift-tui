import BaseDigits

/// A namespace for base-64 utilities.
public
enum Base64
{
    /// Decodes some ``String``-like type containing an ASCII-encoded base-64 string
    /// to some ``RangeReplaceableCollection`` type. Padding is not required.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-64 digits
    /// will be skipped. Decoding will stop upon encountering the first padding
    /// character, even if there are more bytes remaining in the input.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable public
    static func decode<Bytes>(_ ascii:some StringProtocol,
        to _:Bytes.Type = Bytes.self) -> Bytes
        where Bytes:RangeReplaceableCollection<UInt8>
    {
        self.decode(ascii.utf8, to: Bytes.self)
    }
    /// Decodes an ASCII-encoded base-64 string to some ``RangeReplaceableCollection`` type.
    /// Padding is not required.
    ///
    /// Characters (including UTF-8 continuation bytes) that are not base-64 digits
    /// will be skipped. Decoding will stop upon encountering the first padding
    /// character, even if there are more bytes remaining in the input.
    ///
    /// >   Warning:
    ///     This function uses the size of the input string to provide a capacity hint
    ///     for its output, and may over-allocate storage if the input contains many
    ///     non-digit characters.
    @inlinable public
    static func decode<ASCII, Bytes>(_ ascii:ASCII,
        to _:Bytes.Type = Bytes.self) -> Bytes
        where Bytes:RangeReplaceableCollection<UInt8>, ASCII:Sequence<UInt8>
    {
        // https://en.wikipedia.org/wiki/Base64
        var values:Values<ASCII> = .init(ascii),
            bytes:Bytes = .init()
            bytes.reserveCapacity(ascii.underestimatedCount * 3 / 4)
        while   let first:UInt8 = values.next(),
                let second:UInt8 = values.next()
        {
            bytes.append(first << 2 | second >> 4)

            guard let third:UInt8 = values.next()
            else
            {
                break
            }

            bytes.append(second << 4 | third >> 2)

            guard let fourth:UInt8 = values.next()
            else
            {
                break
            }

            bytes.append(third << 6 | fourth)
        }
        return bytes
    }

    /// Encodes a sequence of bytes to a base-64 string with padding if needed.
    @inlinable public
    static func encode<Bytes>(_ bytes:Bytes) -> String where Bytes:Sequence<UInt8>
    {
        self.encode(bytes, padding: true, with: DefaultDigits.self)
    }

    /// Encodes a sequence of bytes to a base-64 string, padding the output with `=` characters
    /// if `padding` is true.
    ///
    /// The main use-case is `padding: false` with ``SafeDigits``.
    @inlinable public
    static func encode<Bytes, Digits>(_ bytes:Bytes,
        padding:Bool,
        with _:Digits.Type) -> String where Bytes:Sequence<UInt8>, Digits:BaseDigits
    {
        var encoded:String = ""
            encoded.reserveCapacity(bytes.underestimatedCount * 4 / 3)
        var bytes:Bytes.Iterator = bytes.makeIterator()
        while let first:UInt8 = bytes.next()
        {
            encoded.append(Digits[first  >> 2])

            guard let second:UInt8 = bytes.next()
            else
            {
                encoded.append(Digits[first  << 4])

                if  padding
                {
                    encoded.append("=")
                    encoded.append("=")
                }

                break
            }

            encoded.append(Digits[first  << 4 | second >> 4])

            guard let third:UInt8 = bytes.next()
            else
            {
                encoded.append(Digits[second << 2])

                if  padding
                {
                    encoded.append("=")
                }
                break
            }

            encoded.append(Digits[second << 2 | third  >> 6])
            encoded.append(Digits[third])
        }
        return encoded
    }
}
