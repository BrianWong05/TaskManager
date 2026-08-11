# Memory pane follows Activity Monitor's model

The Performance memory pane needed to show Cached files and a breakdown of In use. Bolting those onto the old figures (`In use = wired + active + compressed`, `Available = free + inactive`) would have double-counted — `inactive` is largely file cache, so Cached and Available would have overlapped without saying so. We adopted Activity Monitor's model wholesale instead: **In use = App memory + Wired memory + Compressed**, where App memory is `internal_page_count − purgeable_count`, and **Cached files = `external_page_count + purgeable_count`**. Every number on the pane now reconciles, and users can cross-check against Activity Monitor.

`Available` is derived as **`totalPhysical − inUse`**, a residual rather than a sum. The kernel buckets physical memory into more categories than we surface (`speculative`, `throttled`, compressor-internal pages), so a sum is not guaranteed to close, and the arithmetic coherence was the entire point of the change.

## Considered options

- **Keep the old math and add Cached as a loose extra.** Rejected: the breakdown would not have summed to its own headline.
- **Windows 11 parity** (In use / Available / Committed / Cached / Paged pool / Non-paged pool). Rejected: "Committed" and the pools have no honest macOS equivalent; we would have been inventing mappings. The rest of the app follows Win11, so this is a deliberate local deviation.
- **`Available = free + cached` as a literal sum.** Rejected under the same coherence argument.

## Consequences

- **The headline number moved.** In use went from ~24.5 GB to ~26.9 GB on a 36 GB machine, and Available from ~10.7 GB to ~9.1 GB. The mini monitor and the memory history follow automatically — there is one definition of In use in the app.
- **We do not match Activity Monitor exactly, by choice.** AM does not call `host_statistics64`; it goes through `libsysmon`, and it stores `usedMemorySize` and `applicationMemorySize` as separate properties, so it never enforces App + Wired + Compressed = Used. Its Memory Used reads roughly 0.9 GB above ours. When internal coherence and external agreement conflict, coherence wins.
- **~0.86 GB of Available is fictional.** That figure is exactly `hw.memsize − hw.memsize_usable`, a firmware carve-out, and the residual formula parks it in Available. We kept `hw.memsize` for Capacity anyway: a Mac sold as 36 GB reporting 35.1 GB capacity is a worse lie than slop inside a 9 GB Available.
- **`free_count` is deliberately unread.** It already includes `speculative_count` (see `mach/vm_statistics.h`), while `vm_stat(1)` prints "Pages free" with speculative subtracted back out — so a formula transcribed from `vm_stat` output double-subtracts. Deriving Available by subtraction means we never touch the field.
