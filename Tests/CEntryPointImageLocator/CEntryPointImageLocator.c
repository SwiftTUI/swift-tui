/* Compiled out on Windows: dladdr has no Win32 spelling and the
   entry-point launch tests that consume this shim are POSIX-only
   until the Stage 6 test survey of the Windows plan. */
#if !defined(_WIN32)
// `dladdr`/`Dl_info` are GNU extensions on Linux: <dlfcn.h> only declares them
// when `_GNU_SOURCE` is defined. Define it before any include so the symbol is
// visible here even though Swift's `Glibc` overlay does not surface it. Darwin
// declares both unconditionally, so the same translation unit builds there too.
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "CEntryPointImageLocator.h"

#include <dlfcn.h>
#include <stddef.h>

const char *swift_tui_image_path_containing(const void *address) {
  Dl_info info;
  if (dladdr(address, &info) == 0) {
    return NULL;
  }
  return info.dli_fname;
}
#endif
