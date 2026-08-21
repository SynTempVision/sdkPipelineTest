# Reboot/Restart Loop Test — Weekend Findings (2026-08-14 to 2026-08-17)

## Test design

Four units, run continuously over the weekend via `reboot_loop_test.py` / `run_reboot_test.ps1`:

| Label | Host | IP | OS | Action | Cadence |
|---|---|---|---|---|---|
| PT1 | sv-43 | 172.17.103.43 | plain PT | `sudo reboot` | 2 min |
| PTRamOS1 | sv-135 | 172.17.103.135 | RamOS overlay | `sudo reboot` | 2 min |
| PT2 | sv-31 | 172.17.103.31 | plain PT | `pipeline_restart.sh` | 60 sec |
| PTRamOS2 | sv-206 | 172.17.103.206 | RamOS overlay | `pipeline_restart.sh` | 60 sec |

Logs: `RebootLoopTest_{PT1,PTRamOS1,PT2,PTRamOS2}.xlsx` (1920/1920/3826/3825 cycles respectively).
PTRamOS1/PTRamOS2 logs moved to `reports/WeekendTest_PTRamOS_081426/` 2026-08-20 (PT1/PT2's
current master logs continued at `RebootLoopTest_PT1.xlsx`/`PT2.xlsx` in the main dir; PTRamOS1/2
were later renamed PT1NEW/PT2NEW - see `ramos_test_devices.json`).
Automated logging stopped writing around 2026-08-17 07:55 (all four); live diagnostics below were
gathered by hand afterward, morning of 2026-08-17.

## Automated test log summary (artifact-corrected)

The check script's `SEEK_ENUMERATION` field greps `dmesg | tail -n 2000` for "unable to enumerate."
Under the `reboot` action this is meaningful (fresh kernel boot each cycle = fresh dmesg). Under the
`restart` action the kernel never reboots, so a single historical failure line can sit in the
tail-2000 window for days without new dmesg volume pushing it out — confirmed by checking
`ENUM_FAIL_TIME_SEC`: PT2 showed only 2 distinct values across 3779 "FAILED" rows; PTRamOS2 showed
only 1 distinct value across 2023 "FAILED" rows. Treat `restart`-action enum-fail *counts* as
inflated; the timestamps are still real events.

| | PT1 (reboot) | PTRamOS1 (reboot) | PT2 (restart) | PTRamOS2 (restart) |
|---|---|---|---|---|
| SSH unreachable | 1 (0.1%) | 312 (16.2%), ~187 scattered blips | 0 (0.0%) | 1332 (34.8%), one continuous outage Sat 09:42 → end |
| Real enum-fail events | 1 continuous run, Sat 13:07 → Mon 07:55 (42.5 hrs, never recovered) | 227 across ~187 runs, nearly all self-cleared in 1-2 cycles | 2 real events only | 1 real event only (~9.7 hrs post-boot) |
| USB resets (max) | 1 | 1 | 105 | 432 (before it went dark) |
| CPU temp avg | 57.1°C | 61.3°C | 64.2°C | 60.9°C |

## Live diagnostics (2026-08-17, morning after)

### Every unit's Seek camera is absent from USB, confirmed directly
`lsusb -v` / `lsusb -t` / `/sys/kernel/debug/usb/devices` on all four show only the root hub (1d6b:0002)
and the onboard 4-port Terminus hub (1a40:0101) — no Seek Thermal device (289d) anywhere in the tree,
on any of the four units. This is a direct topology dump, not inferred from a dmesg keyword — the
camera is electrically gone right now on all four simultaneously.

### image.pgm content (not just size/freshness) — all four are producing no real image
| Unit | Size | Last write | Content |
|---|---|---|---|
| PT1 (sv-43) | 17 bytes | rewritten periodically | header only, zero pixel bytes |
| PTRamOS1 (sv-135) | 153617 | frozen since **2026-08-14 14:19:35** (~67 hrs stale even after a same-morning reboot) | valid header + all-zero pixel data |
| PT2 (sv-31) | 153617/0 (caught mid truncate-rewrite race) | actively rewritten | valid header + all-zero pixel data |
| PTRamOS2 (sv-206) | 153600 | actively rewritten (~20 min old at check time) | **no header at all** — starts at zero bytes from offset 0 (write corruption, distinct from the other three) |

The check script's `IMAGE_OK` (size >1000 bytes + age <60s) cannot distinguish a real frame from a
correctly-sized all-zero one — it passed PTRamOS1's frozen frame and PT2's actively-refreshed blank
frame throughout the whole weekend run.

### PTRamOS2 (sv-206): confirmed disk-full, cascading failure
- `df -h`: overlay `900M 900M 0 100%` — literally 0 bytes available.
- `dmesg -T > file` itself failed: `write failed: No space left on device`.
- `journalctl --disk-usage`: active journal file reported "truncated, ignoring file" (corrupted by ENOSPC).
- `uptime`: 2 days 20:24 — no kernel reboot since the test's first boot (expected: `restart` action never
  reboots the kernel), so 66+ hours of log volume accumulated with nothing ever clearing the overlay.
- Contrast with PTRamOS1 (sv-135), same RAM-overlay OS: overlay only 29% used (260M/900M), because its
  2-minute reboot cadence wipes the tmpfs clean every cycle — this is *why* PTRamOS1 never hit the
  disk-full cascade despite sharing the same fixed-size RAM budget design.
- SFTP push failures in the automated log (`OSError: size mismatch in put!`) and total SSH unreachability
  from Sat 09:42 onward are downstream consequences of this, not a separate fault.
- **What's actually filling the 900M overlay** (`du -h --max-depth=1`, sudo, run 2026-08-17 morning):
  `/var/log` = 754M (the large majority) — of which journald is only 224M, leaving ~530M unaccounted
  for in `/var/log`; `rsyslogd` is running on this unit (confirmed in process list) and is the likely
  source of the rest (plain-text syslog with no rotation over 2.5 days) but not yet directly confirmed —
  next step is `sudo du -h --max-depth=1 /var/log` to break it down further. `/var/lib` = 306M (includes
  153M `/var/lib/mysql`, unrotated over the same period). `/var/cache` = 250M. Note: `du /` on an overlay
  reports the merged upper+lower view (3.2G total) — much bigger than `df`'s 900M, which is specifically
  the writable tmpfs upper layer; `/var/log`'s growth is what's actually consuming that budget.
  Also noted while running these checks: `sudo` itself throws `unable to resolve host sv-206` on every
  invocation — DNS/hostname resolution is broken on this unit too, likely a further downstream effect of
  the disk-full state (possibly a failed write to `/etc/hosts` or resolver-related file).

### Process state differs meaningfully between units right now
- **PT1 (sv-43)**: neither `rtsp-seek-server` nor `rtsp-color-server` appear in the process table at all —
  worse than the others; the pipeline isn't spinning-and-failing, it simply isn't running.
- **PTRamOS1 (sv-135)**: both pipeline processes alive (`rtsp-seek-server` 5.6% CPU, `rtsp-color-server`
  36.3% CPU) but producing the frozen zero-frame from day one.
- **PT2 (sv-31) / PTRamOS2 (sv-206)**: `rtsp-color-server` pinned at ~78-80% CPU continuously since
  boot on Aug 14 (3193-3297 CPU-minutes over ~2.5 days) — a heavy sustained load not seen on the other
  two. `rtsp-seek-server` + a self-referential `gst-launch-1.0 rtspsrc rtsp://127.0.0.1:8554 ! filesink
  /dev/null` process both restart together on each `pipeline_restart.sh` cycle (recent PIDs, ~07:36-07:54
  start times) — this loopback process is likely why RTSP:8554 always reports "UP" even with a dead
  source; worth understanding but not yet explained.
- PT1 and PTRamOS1 both show `uptime` of exactly 2:07 at check time — both were freshly rebooted
  (independent of the automated test, which had already stopped) shortly before this diagnostic pass,
  and the camera still did not return on either — rules out "just needs one more reboot."

## Conclusion

This is not a clean "RamOS vs plain PT" or "reboot vs restart" story. All four units hit the same root
failure — the Seek camera drops off USB and never comes back — confirmed identically and directly across
all four right now. The `reboot`-cadence units re-trigger it every 2 minutes (PT1 permanently, from
Sat 13:07 onward; PTRamOS1's camera died in the first 20 minutes and stayed dead); the `restart`-cadence
units accumulate USB resets under load until they hit the same wall hours in. Given the identical
enumeration-failure error codes (`-110`/`-62`) and near-identical boot-time-offset timing recorded
earlier in this investigation, plus now literal camera absence on all four simultaneously, the most
likely explanation is something shared across the bench (power rail, PoE source, or a firmware/kernel
USB-timing quirk common to this hardware batch) rather than four independent camera failures.

**Separately**, PTRamOS2's disk-full/journald cascade is a real, independent finding about the RamOS
design: a fixed-size RAM overlay has zero tolerance for sustained kernel log volume (from *any* cause,
not just this USB issue) unless something periodically clears it. PTRamOS1 only avoided this by accident
of its 2-minute reboot cadence. A production RamOS deployment needs either journald size limits
(`SystemMaxUse=`/`RuntimeMaxUse=` in journald.conf) or a periodic overlay-clearing reboot to survive
this failure mode long-term.

## Open items / next steps
- Physical inspection: reseat Seek camera USB connector on all four; check whether the bench shares a
  common power supply/PoE source across units.
- `vcgencmd get_throttled` / `vcgencmd measure_volts core` not yet captured — would confirm or rule out
  an undervoltage event as the trigger.
- Explain the self-referential `gst-launch rtspsrc ... /dev/null` process — built-in keepalive/watchdog,
  or leftover from testing?
- Check `systemctl status` for whatever supervises `rtsp-seek-server` on PT1 (sv-43) — is it crash-looping
  or fully stopped?
- Fix the check script's `IMAGE_OK` validation to inspect pixel content (not just size+age) so a
  correctly-sized all-zero frame doesn't read as healthy.
- Add journald `SystemMaxUse=`/`RuntimeMaxUse=` limits to the RamOS image before any future long-duration
  test or production deployment.
- Break down `/var/log`'s 754M on PTRamOS2 further (`sudo du -h --max-depth=1 /var/log`) to confirm
  rsyslog (vs. something else) as the ~530M non-journald contributor; add log rotation/size caps for
  whatever it turns out to be, same rationale as the journald fix above.
- Investigate the `sudo: unable to resolve host` DNS/resolver breakage on PTRamOS2 — separate symptom of
  the disk-full cascade, not yet root-caused.

**Session paused here 2026-08-17 — mid-investigation, not concluded.** Live diagnostics were captured
for all four units' USB/image/process state and PTRamOS2's disk breakdown; physical inspection and the
open items above are still outstanding.
