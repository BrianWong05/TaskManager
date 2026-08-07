// Daemon/Daemon-Bridging-Header.h
// C surface for the daemon's privileged collectors (same libproc set the app
// uses unprivileged — root sees everything).

#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <signal.h>
