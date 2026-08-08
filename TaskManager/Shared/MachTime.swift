// Shared/MachTime.swift
// Compiled into both the app and the daemon.

import Foundation

/// Cached once: the timebase cannot change while the process lives, and the
/// process-table path converts ~1000 values per tick.
private let machTimebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()

/// proc_taskinfo's `pti_total_user` / `pti_total_system` are Mach absolute
/// time units, NOT nanoseconds, despite "total time" in the header comment.
/// On Apple Silicon the timebase is 125/3 (41.67 ns per unit), so treating
/// them as nanoseconds underreports every CPU percentage by ~41.7x — a
/// process at 4 % of total CPU renders as 0.1 %. Intel's timebase is 1/1,
/// which is why the raw values look correct there.
///
/// Verified against `ps -o time`: for one process ps reported 144.66 s and
/// this conversion 144.66 s, versus 3.47 s unconverted.
func machTimeToNanoseconds(_ machTime: UInt64) -> UInt64 {
    machTime * UInt64(machTimebase.numer) / UInt64(machTimebase.denom)
}
