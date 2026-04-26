/// Much of this module’s functionality is `@inlinable` and would require users of ``MD5`` to
/// also import ``InlineBuffer`` along with it.  However, ``InlineBuffer`` is an implementation
/// detail of ``MD5`` and clients should not interact with it directly.
@_exported import struct InlineBuffer.InlineBuffer
