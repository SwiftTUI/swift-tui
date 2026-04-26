/// Much of this module’s functionality is `@inlinable` and would require users of ``SHA1`` to
/// also import ``InlineBuffer`` along with it.  However, ``InlineBuffer`` is an implementation
/// detail of ``SHA1`` and clients should not interact with it directly.
@_exported import struct InlineBuffer.InlineBuffer
