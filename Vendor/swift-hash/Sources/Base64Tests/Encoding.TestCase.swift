import Base64

extension Encoding
{
    struct TestCase
    {
        let name:String
        let degenerate:String?
        let canonical:String
        let expected:[UInt8]

        init(name:String,
            degenerate:String? = nil,
            canonical:String,
            expected:[UInt8])
        {
            self.name = name
            self.degenerate = degenerate
            self.canonical = canonical
            self.expected = expected
        }
    }
}
extension Encoding.TestCase
{
    init<UTF8>(name:String,
        degenerate:String? = nil,
        canonical:String,
        expected:UTF8) where UTF8:Collection, UTF8.Element == UInt8
    {
        self.init(name: name,
            degenerate: degenerate,
            canonical: canonical,
            expected: .init(expected))
    }
    init(name:String,
        degenerate:String? = nil,
        canonical:String,
        expected:String)
    {
        self.init(name: name,
            degenerate: degenerate,
            canonical: canonical,
            expected: expected.utf8)
    }
}
