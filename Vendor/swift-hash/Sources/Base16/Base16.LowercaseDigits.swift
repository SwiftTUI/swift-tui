import BaseDigits

extension Base16
{
    public
    enum LowercaseDigits
    {
    }
}
extension Base16.LowercaseDigits:BaseDigits
{
    @inlinable public static
    subscript(remainder:UInt8) -> UInt8
    {
        (remainder < 10 ? 0x30 : 0x61 - 10) &+ remainder
    }
}
