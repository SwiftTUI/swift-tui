import MD5
import Testing

//  Test vectors from: https://datatracker.ietf.org/doc/html/rfc1321
@Suite
struct Hashing
{
    private
    static var binary:[(MD5, [UInt8])]
    {
        if #available(
            macOS 13.3,
            macCatalyst 16.4,
            iOS 16.4,
            tvOS 16.4,
            visionOS 1.0,
            watchOS 9.4,
            *)
        {
            [
                (0xd41d8cd98f00b204e9800998ecf8427e, []),
                (0x0cc175b9c0f1b6a831c399e269772661, [0x61]),
                (0x900150983cd24fb0d6963f7d28e17f72, [0x61, 0x62, 0x63]),
            ]
        }
        else
        {
            []
        }
    }

    @Test(arguments: Self.binary)
    static func binary(_ test:(expected:MD5, input:[UInt8]))
    {
        let md5:MD5 = .init(hashing: test.input)
        #expect(md5 == test.expected)
    }

    private
    static var string:[(MD5, String)]
    {
        if #available(
            macOS 13.3,
            macCatalyst 16.4,
            iOS 16.4,
            tvOS 16.4,
            visionOS 1.0,
            watchOS 9.4,
            *)
        {
            [
                (
                    0xf96b697d7cb7938d525a2f31aaf161d0,
                    "message digest"
                ),
                (
                    0xc3fcd3d76192e4007dfb496cca67e13b,
                    "abcdefghijklmnopqrstuvwxyz"
                ),
                (
                    0xd174ab98d277d9f5a5611c2c9f419d9f,
                    """
                    ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789
                    """
                ),
                (
                    0x57edf4a22be3c955ac49da2e2107b67a,
                    """
                    1234567890123456789012345678901234567890\
                    1234567890123456789012345678901234567890
                    """
                ),
            ]
        }
        else
        {
            []
        }
    }

    @Test(arguments: Self.string)
    static func string(_ test:(expected:MD5, input:String))
    {
        let md5:MD5 = .init(hashing: test.input.utf8)
        #expect(md5 == test.expected)
    }
}
