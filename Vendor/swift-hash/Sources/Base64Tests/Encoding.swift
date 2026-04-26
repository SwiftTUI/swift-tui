import Base64
import Testing

@Suite
struct Encoding
{
    private
    static let binary:[TestCase] = [
        .init(name: "all",
            degenerate:
            """
            AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v\
            MDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5f\
            YGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6P\
            kJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/\
            wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v\
            8PHy8/T19vf4+fr7/P3+/w
            """,
            canonical:
            """
            AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v\
            MDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5f\
            YGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6P\
            kJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/\
            wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v\
            8PHy8/T19vf4+fr7/P3+/w==
            """,
            expected: 0x00 ... 0xff),

        .init(name: "reversed",
            degenerate:
            """
            //79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eDf3t3c29rZ2NfW1dTT0tHQ\
            z87NzMvKycjHxsXEw8LBwL++vby7urm4t7a1tLOysbCvrq2sq6qpqKempaSjoqGg\
            n56dnJuamZiXlpWUk5KRkI+OjYyLiomIh4aFhIOCgYB/fn18e3p5eHd2dXRzcnFw\
            b25tbGtqaWhnZmVkY2JhYF9eXVxbWllYV1ZVVFNSUVBPTk1MS0pJSEdGRURDQkFA\
            Pz49PDs6OTg3NjU0MzIxMC8uLSwrKikoJyYlJCMiISAfHh0cGxoZGBcWFRQTEhEQ\
            Dw4NDAsKCQgHBgUEAwIBAA
            """,
            canonical:
            """
            //79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eDf3t3c29rZ2NfW1dTT0tHQ\
            z87NzMvKycjHxsXEw8LBwL++vby7urm4t7a1tLOysbCvrq2sq6qpqKempaSjoqGg\
            n56dnJuamZiXlpWUk5KRkI+OjYyLiomIh4aFhIOCgYB/fn18e3p5eHd2dXRzcnFw\
            b25tbGtqaWhnZmVkY2JhYF9eXVxbWllYV1ZVVFNSUVBPTk1MS0pJSEdGRURDQkFA\
            Pz49PDs6OTg3NjU0MzIxMC8uLSwrKikoJyYlJCMiISAfHh0cGxoZGBcWFRQTEhEQ\
            Dw4NDAsKCQgHBgUEAwIBAA==
            """,
            expected: (0x00 ... 0xff).reversed()),
    ]

    private
    static let string:[TestCase] = [
        .init(name: "empty",
            canonical: "",
            expected: ""),

        .init(name: "single",
            degenerate: "YQ",
            canonical: "YQ==",
            expected: "a"),

        .init(name: "double",
            degenerate: "YWI",
            canonical: "YWI=",
            expected: "ab"),

        .init(name: "triple",
            canonical: "YWJj",
            expected: "abc"),

        .init(name: "basic",
            canonical: "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu",
            expected: "Many hands make light work."),

        .init(name: "whitespace",
            degenerate:
            """
            T\u{0C}WFueSBoY W5kc\ryBtYWt\tlIGxpZ2
            h0IHd

            vcmsu
            """,
            canonical: "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu",
            expected: "Many hands make light work."),

        .init(name: "padding-11-16",
            degenerate: "bGlnaHQgd29yay4",
            canonical: "bGlnaHQgd29yay4=",
            expected: "light work."),

        .init(name: "padding-10-16",
            degenerate: "bGlnaHQgd29yaw",
            canonical: "bGlnaHQgd29yaw==",
            expected: "light work"),

        .init(name: "padding-9-12",
            canonical: "bGlnaHQgd29y",
            expected: "light wor"),

        .init(name: "padding-8-12",
            degenerate: "bGlnaHQgd28",
            canonical: "bGlnaHQgd28=",
            expected: "light wo"),

        .init(name: "padding-7-12",
            degenerate: "bGlnaHQgdw",
            canonical: "bGlnaHQgdw==",
            expected: "light w"),
    ]

    @Test(arguments: Self.binary + Self.string)
    static func defaultDigits(_ test:TestCase) throws
    {
        #expect(test.expected == Base64.decode(test.canonical.utf8, to: [UInt8].self))
        #expect(test.canonical == Base64.encode(test.expected))

        if  let degenerate:String = test.degenerate
        {
            let decoded:[UInt8] = Base64.decode(degenerate, to: [UInt8].self)
            let encoded:String = Base64.encode(decoded)
            #expect(decoded == test.expected)
            #expect(encoded == test.canonical)
        }
    }

    @Test
    static func urlSafeDigits()
    {
        let encoded:String = Base64.encode("<<???>>".utf8,
            padding: false,
            with: Base64.SafeDigits.self)

        #expect(encoded == "PDw_Pz8-Pg")
    }
}
