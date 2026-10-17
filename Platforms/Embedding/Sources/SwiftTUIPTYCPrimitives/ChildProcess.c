/* Compiled out on Windows: forkpty/ioctl have no Win32 equivalent and the
   consuming targets drop this dependency edge there. */
#if !defined(_WIN32)
#include "SwiftTUIPTYCPrimitives.h"

#include <signal.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/resource.h>
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

  // dup2(fd, fd) leaves FD_CLOEXEC intact when allocation reused a closed
  // standard descriptor. The three child streams must survive exec either way.
  for (int fd = STDIN_FILENO; fd <= STDERR_FILENO; fd++) {
    if (fcntl(fd, F_SETFD, 0) < 0) { return -1; }
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
  // Capture the descriptor bound before fork. Only async-signal-safe calls
  // run in the child. Closing the inherited table also covers another thread
  // allocating a PTY between openpty and its FD_CLOEXEC installation.
  struct rlimit descriptor_limit;
  if (getrlimit(RLIMIT_NOFILE, &descriptor_limit) != 0) { return -1; }
  long descriptor_bound = sysconf(_SC_OPEN_MAX);
  if (descriptor_bound < 0) { return -1; }
  if (descriptor_limit.rlim_max != RLIM_INFINITY
      && descriptor_limit.rlim_max > (rlim_t)descriptor_bound
      && descriptor_limit.rlim_max <= INT_MAX) {
    descriptor_bound = (long)descriptor_limit.rlim_max;
  }
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

  (void)master_fd;
  for (int fd = STDERR_FILENO + 1; fd < descriptor_bound; fd++) {
    close(fd);
  }

  if (working_directory != NULL && chdir(working_directory) != 0) {
    swift_tui_pty_exit_127();
  }

  execve(argv[0], argv, envp);
  swift_tui_pty_exit_127();
}
#endif
