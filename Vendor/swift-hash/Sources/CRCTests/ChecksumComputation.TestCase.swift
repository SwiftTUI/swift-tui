import CRC

extension ChecksumComputation
{
    struct TestCase
    {
        let name:String
        let message:String
        let expected:CRC32

        init(name:String,
            message:String,
            expected:CRC32)
        {
            self.name = name
            self.message = message
            self.expected = expected
        }
    }
}
