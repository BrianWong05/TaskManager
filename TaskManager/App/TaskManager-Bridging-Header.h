// App/TaskManager-Bridging-Header.h
// C surface for the unprivileged metrics collectors (spec §5). Exposes
// libproc + sysctl declarations to Swift; no extra link flags needed
// (libproc ships inside libSystem).

#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <signal.h>
