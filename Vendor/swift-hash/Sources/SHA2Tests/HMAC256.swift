import Base16
import SHA2
import Testing

@Suite
struct HMAC256
{
    // https://datatracker.ietf.org/doc/html/rfc4231
    static let cases:[TestCase] = [
        .init(name: "1",
            key:
            """
            0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b
            0b0b0b0b
            """,
            message: "4869205468657265",
            hmac256:
            """
            b0344c61d8db38535ca8afceaf0bf12b
            881dc200c9833da726e9376c2e32cff7
            """
        ),

        .init(name: "2",
            key: "4a656665",
            message:
            """
            7768617420646f2079612077616e7420
            666f72206e6f7468696e673f
            """,
            hmac256:
            """
            5bdcc146bf60754e6a042426089575c7
            5a003f089d2739839dec58b964ec3843
            """
        ),

        .init(name: "3",
            key:
            """
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaa
            """,
            message:
            """
            dddddddddddddddddddddddddddddddd
            dddddddddddddddddddddddddddddddd
            dddddddddddddddddddddddddddddddd
            dddd
            """,
            hmac256:
            """
            773ea91e36800e46854db8ebd09181a7
            2959098b3ef8c122d9635514ced565fe
            """
        ),

        .init(name: "4",
            key:
            """
            0102030405060708090a0b0c0d0e0f10
            111213141516171819
            """,
            message:
            """
            cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
            cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
            cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
            cdcd
            """,
            hmac256:
            """
            82558a389a443c0ea4cc819899f2083a
            85f0faa3e578f8077a2e3ff46729665b
            """
        ),

        .init(name: "5",
            key:
            """
            0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c
            0c0c0c0c
            """,
            message:
            """
            546573742057697468205472756e6361
            74696f6e
            """,
            hmac256:
            """
            a3b6167473100ee06e0c796c2955552b
            fa6f7c0a6a8aef8b93f860aab0cd20c5
            """
        ),

        .init(name: "6",
            key:
            """
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaa
            """,
            message:
            """
            54657374205573696e67204c61726765
            72205468616e20426c6f636b2d53697a
            65204b6579202d2048617368204b6579
            204669727374
            """,
            hmac256:
            """
            60e431591ee0b67f0d8a26aacbf5b77f
            8e0bc6213728c5140546040f0ee37f54
            """
        ),

        .init(name: "7",
            key:
            """
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            aaaaaa
            """,
            message:
            """
            54686973206973206120746573742075
            73696e672061206c6172676572207468
            616e20626c6f636b2d73697a65206b65
            7920616e642061206c61726765722074
            68616e20626c6f636b2d73697a652064
            6174612e20546865206b6579206e6565
            647320746f2062652068617368656420
            6265666f7265206265696e6720757365
            642062792074686520484d414320616c
            676f726974686d2e
            """,
            hmac256:
            """
            9b09ffa71b942fcb27635fbcd5b0e944
            bfdc63644f0713938a7f51535c3a35e2
            """
        ),
    ]

    @Test(arguments: Self.cases)
    static func binary(_ test:TestCase)
    {
        let key:[UInt8] = Base16.decode(test.key.utf8)
        let message:[UInt8] = Base16.decode(test.message.utf8)

        let computed:SHA256 = .init(authenticating: message, key: key)

        #expect(computed == test.expected)
    }
}
