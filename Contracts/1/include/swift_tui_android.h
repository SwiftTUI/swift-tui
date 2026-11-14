#ifndef SWIFT_TUI_ANDROID_H
#define SWIFT_TUI_ANDROID_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ABI 1 uses fixed-width values on little-endian Android arm64/x86_64.
 * Wire capabilities are independent of these native operation bits. */
#define SWIFT_TUI_ANDROID_ABI_MAJOR 1u
#define SWIFT_TUI_ANDROID_ABI_MINOR 1u
#define SWIFT_TUI_ANDROID_ABI_INFO_BYTES 32u
#define SWIFT_TUI_ANDROID_OP_CAPABILITIES (1u << 0)
#define SWIFT_TUI_ANDROID_OP_RESYNC (1u << 1)
#define SWIFT_TUI_ANDROID_OP_ACCESSIBILITY (1u << 2)
#define SWIFT_TUI_ANDROID_OP_CLIPBOARD (1u << 3)
#define SWIFT_TUI_ANDROID_OP_DIAGNOSTICS (1u << 4)
/* Minor 1. */
#define SWIFT_TUI_ANDROID_OP_OPEN_LINK (1u << 5)
#define SWIFT_TUI_ANDROID_OP_CLIPBOARD_TAKE (1u << 6)
#define SWIFT_TUI_ANDROID_OP_TEXT_INPUT (1u << 7)

typedef int64_t swift_tui_android_handle;
typedef struct swift_tui_android_abi_info {
  uint32_t struct_bytes;
  uint32_t major;
  uint32_t minor;
  uint32_t handle_bits;
  uint32_t count_bits;
  uint32_t scalar_bits;
  uint32_t operations;
  uint32_t reserved;
} swift_tui_android_abi_info;

/* Returns the current struct size. A null buffer, negative or zero capacity
 * is a size query. Otherwise copies min(capacity, struct size) bytes, without
 * retaining the buffer. A short query is supported and has no lifecycle effect. */
int32_t swift_tui_android_get_abi_info(uint8_t *buffer, int32_t capacity);

/* Required operations. Install the executor before the application factory.
 * All lifecycle, tick, resize and input calls belong to that same main thread. */
void swift_tui_android_install_executor(void);
swift_tui_android_handle swift_tui_android_create_host(void);
void swift_tui_android_start(swift_tui_android_handle handle);
int32_t swift_tui_android_tick(swift_tui_android_handle handle);
void swift_tui_android_stop(swift_tui_android_handle handle);
void swift_tui_android_destroy(swift_tui_android_handle handle);
void swift_tui_android_resize(swift_tui_android_handle handle, int32_t columns,
                              int32_t rows, double cell_width, double cell_height);
void swift_tui_android_send_input(swift_tui_android_handle handle,
                                  const uint8_t *bytes, int32_t count);
int32_t swift_tui_android_copy_latest_frame(swift_tui_android_handle handle,
                                           uint8_t *buffer, int32_t capacity);

/* Optional operations. Check both the advertised bit and the symbol. Legacy
 * libraries without the query are admitted only with every required symbol. */
int32_t swift_tui_android_declare_capabilities(swift_tui_android_handle handle,
                                              const uint8_t *bytes, int32_t count);
int32_t swift_tui_android_request_resync(swift_tui_android_handle handle,
                                        const uint8_t *bytes, int32_t count);
int32_t swift_tui_android_accessibility_action(swift_tui_android_handle handle,
                                              const uint8_t *bytes, int32_t count);
int32_t swift_tui_android_copy_clipboard_text(swift_tui_android_handle handle,
                                             uint8_t *buffer, int32_t capacity);
/* Minor 1. Returns -1 when no clipboard write is pending, otherwise the UTF-8
 * byte count of the pending text: 0 is a pending empty write, which
 * copy_clipboard_text neither reports nor drains. A null or undersized buffer
 * is a query; a large-enough buffer copies and drains, and an empty text needs
 * no capacity. The host admits an empty write only after the first call on
 * that handle. */
int32_t swift_tui_android_take_clipboard_text(swift_tui_android_handle handle,
                                             uint8_t *buffer, int32_t capacity);
int64_t swift_tui_android_diag(void);
/* Minor 1. Same query/copy convention as copy_clipboard_text, over a queue of
 * link destinations: a successful copy removes the oldest one, and 0 means
 * none is pending. The host queues a destination only after the first call on
 * that handle. */
int32_t swift_tui_android_copy_open_link(swift_tui_android_handle handle,
                                         uint8_t *buffer, int32_t capacity);
/* Minor 1. One complete UTF-8 input-method edit record: the focused editor's
 * whole text, directed UTF-16 selection and composing range. See
 * profiles/android-abi.md. */
int32_t swift_tui_android_text_input(swift_tui_android_handle handle,
                                     const uint8_t *bytes, int32_t count);

#ifdef __cplusplus
}
static_assert(sizeof(swift_tui_android_handle) == 8, "handle width");
static_assert(sizeof(swift_tui_android_abi_info) == 32, "ABI info layout");
static_assert(sizeof(double) == 8, "scalar width");
#else
_Static_assert(sizeof(swift_tui_android_handle) == 8, "handle width");
_Static_assert(sizeof(swift_tui_android_abi_info) == 32, "ABI info layout");
_Static_assert(sizeof(double) == 8, "scalar width");
#endif

#endif
