import Base16
import SHA2

extension HMAC256
{
    struct TestCase
    {
        let name:String
        let key:String,
            message:String,
            expected:SHA256

        init(name:String, key:String, message:String, hmac256 expected:SHA256)
        {
            self.name = name
            self.key = key
            self.message = message
            self.expected = expected
        }
    }
}
