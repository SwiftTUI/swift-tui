#include "SwiftTUIPTYCPrimitives.h"

#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

__attribute__((noreturn)) static void swift_tui_pty_exit_127(void) {
  _exit(127);
}

static int swift_tui_pty_make_controlling_terminal(int slave_fd) {
  if (setsid() < 0) {
    return -1;
  }

#ifdef TIOCSCTTY
  if (ioctl(slave_fd, TIOCSCTTY, 0) < 0) {
    return -1;
  }
#endif

  if (dup2(slave_fd, STDIN_FILENO) < 0) {
    return -1;
  }
  if (dup2(slave_fd, STDOUT_FILENO) < 0) {
    return -1;
  }
  if (dup2(slave_fd, STDERR_FILENO) < 0) {
    return -1;
  }

  if (slave_fd > STDERR_FILENO) {
    close(slave_fd);
  }

  return 0;
}

static void swift_tui_pty_restore_default_signals(void) {
  sigset_t empty_set;
  sigemptyset(&empty_set);
  sigprocmask(SIG_SETMASK, &empty_set, NULL);

  signal(SIGHUP, SIG_DFL);
  signal(SIGINT, SIG_DFL);
  signal(SIGQUIT, SIG_DFL);
  signal(SIGTERM, SIG_DFL);
}

pid_t swift_tui_pty_fork_exec(
  int master_fd,
  int slave_fd,
  const char *working_directory,
  char *const argv[],
  char *const envp[]
) {
  pid_t pid = fork();
  if (pid != 0) {
    return pid;
  }

  if (argv == NULL || argv[0] == NULL) {
    swift_tui_pty_exit_127();
  }

  swift_tui_pty_restore_default_signals();

  if (swift_tui_pty_make_controlling_terminal(slave_fd) != 0) {
    swift_tui_pty_exit_127();
  }

  if (master_fd >= 0) {
    close(master_fd);
  }

  if (working_directory != NULL && chdir(working_directory) != 0) {
    swift_tui_pty_exit_127();
  }

  execve(argv[0], argv, envp);
  swift_tui_pty_exit_127();
}
