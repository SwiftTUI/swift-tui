import MD5
import Testing

@Suite
struct ParsingAndFormatting
{
    @Test
    static func strings() throws
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
            let string:String = "d41d8cd98f00b204e9800998ecf8427e"
            let hash:MD5 =     0xd41d8cd98f00b204e9800998ecf8427e

            let parsed:MD5 = try #require(.init(string))
            #expect(parsed == hash)
            #expect(string == "\(hash)")
        }
    }
}
