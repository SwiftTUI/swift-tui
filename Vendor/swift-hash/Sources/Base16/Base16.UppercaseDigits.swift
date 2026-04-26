import BaseDigits

extension Base16
{
    public
    enum UppercaseDigits
    {
    }
}
extension Base16.UppercaseDigits:BaseDigits
{
    @inlinable public static
    subscript(remainder:UInt8) -> UInt8
    {
        (remainder < 10 ? 0x30 : 0x41 - 10) &+ remainder
    }
}
