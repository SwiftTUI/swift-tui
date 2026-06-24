#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(WASILibc)
  import WASILibc
#elseif canImport(ucrt)
  import ucrt
#endif

package func powDouble(
  _ base: Double,
  _ exponent: Double
) -> Double {
  #if canImport(Darwin)
    Darwin.pow(base, exponent)
  #elseif canImport(Glibc)
    Glibc.pow(base, exponent)
  #elseif canImport(Android)
    Android.pow(base, exponent)
  #elseif canImport(WASILibc)
    WASILibc.pow(base, exponent)
  #elseif canImport(ucrt)
    ucrt.pow(base, exponent)
  #else
    fatalError("powDouble is unavailable on this platform.")
  #endif
}
