// App/TaskManager-Bridging-Header.h
// C surface for the unprivileged metrics collectors (spec §5). Exposes
// libproc + sysctl declarations to Swift; no extra link flags needed
// (libproc ships inside libSystem).

#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <signal.h>
#include <utmpx.h>

// SPI (libSystem, stable since 10.14): the process macOS holds responsible
// for `pid` — e.g. Safari for a com.apple.WebKit.WebContent helper. Same
// attribution Activity Monitor and the out-of-memory dialog use. Returns the
// pid itself for self-responsible processes, -1 on failure.
extern pid_t responsibility_get_pid_responsible_for_pid(pid_t pid);
