#ifndef SWIFT_TUI_PTY_C_PRIMITIVES_H
#define SWIFT_TUI_PTY_C_PRIMITIVES_H

#if !defined(_WIN32)

#include <sys/types.h>

pid_t swift_tui_pty_fork_exec(
  int master_fd,
  int slave_fd,
  const char *working_directory,
  char *const argv[],
  char *const envp[]
);

#endif /* !defined(_WIN32) */

#endif /* SWIFT_TUI_PTY_C_PRIMITIVES_H */
