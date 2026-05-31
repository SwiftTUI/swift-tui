#ifndef SWIFT_TUI_C_ENTRY_POINT_IMAGE_LOCATOR_H
#define SWIFT_TUI_C_ENTRY_POINT_IMAGE_LOCATOR_H

// Returns the filesystem path of the loaded image (executable or shared
// object) that contains `address`, or NULL when it cannot be resolved.
//
// This wraps `dladdr`. On Linux `dladdr`/`Dl_info` are GNU extensions guarded
// by `_GNU_SOURCE` in <dlfcn.h>, and Swift's `Glibc` overlay does not surface
// them — so the test that needs the loaded test-bundle path (to locate sibling
// fixture executables) cannot call `dladdr` directly there. The C side defines
// `_GNU_SOURCE`, exposing the symbol on every platform behind one signature.
//
// The returned pointer is owned by the dynamic linker and stays valid for as
// long as the image remains loaded.
const char *swift_tui_image_path_containing(const void *address);

#endif
