extension KeyDerivation
{
    struct TestCase
    {
        let name:String
        let password:String,
            salt:String,
            iterations:Int,
            derived:[UInt8]

        init(name:String, password:String, salt:String, iterations:Int, derived:[UInt8])
        {
            self.name = name
            self.password = password
            self.salt = salt
            self.iterations = iterations
            self.derived = derived
        }
    }
}
