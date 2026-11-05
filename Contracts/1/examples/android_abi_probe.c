#include "../include/swift_tui_android.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

/* Link this caller against the application's actual native host library. */
int main(void) {
  assert(swift_tui_android_get_abi_info(NULL, 0) >= 32);
  swift_tui_android_abi_info info = {0};
  int32_t size = swift_tui_android_get_abi_info((uint8_t *)&info, sizeof(info));
  assert(size >= 32 && info.struct_bytes >= 32);
  assert(info.major == SWIFT_TUI_ANDROID_ABI_MAJOR);
  assert(info.handle_bits == 64 && info.count_bits == 32 && info.scalar_bits == 64);
  for (int32_t capacity = -1; capacity <= 40; ++capacity) {
    uint8_t bytes[40];
    memset(bytes, 0xA5, sizeof(bytes));
    assert(swift_tui_android_get_abi_info(bytes, capacity) == size);
    int32_t copied = capacity < 0 ? 0 : capacity < size ? capacity : size;
    for (int32_t i = copied; i < 40; ++i) assert(bytes[i] == 0xA5);
  }
  printf("{\"major\":%u,\"minor\":%u,\"bytes\":%u,\"operations\":%u}\n",
         info.major, info.minor, info.struct_bytes, info.operations);
  return 0;
}
