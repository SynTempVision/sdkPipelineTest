# New vs. Old Pipeline Test Plan

## Goal

Determine whether the new SDK pipeline (`seekcamera-gstreamer`, currently v3) is better,
the same, or worse than the old pipeline (`rtsp-seek-server`).

### Things I am looking for

- Seek USB enumeration reliability
- Ability to self-recover from transient USB errors without a full restart/exit
- Overall stability (CPU load, network behavior)
- Faults / bugs in either system

This is directly testable: if the new pipeline is better, it should show fewer/shorter Seek
enumeration failures, fewer restart events per unit of uptime, and measurable self-recovery
events that the old pipeline has no equivalent for.

## Test Design

**Option 1 - Matched pairs.** Two stress conditions, each run on one old-pipeline unit and
one new-pipeline unit in parallel, so results are directly comparable pair-by-pair rather
than pooled:

| Unit | Pipeline | Stress action | Cycle |
|---|---|---|---|
| PT1 | old (`rtsp-seek-server`) | full reboot | 2 min |
| PT1NEW | new (`seekcamera-gstreamer`) | full reboot | 2 min |
| PT2 | old (`rtsp-seek-server`) | pipeline restart | 60 sec |
| PT2NEW | new (`seekcamera-gstreamer`) | pipeline restart | 60 sec |

**Option 2 - Steady-state endurance.** Leave each pipeline running normally, with no
deliberate reboot/restart stress at all, to catch slow-building problems (memory leaks, CPU
drift) that a constantly-restarting stress loop would mask by resetting state every cycle.

Every cycle, each unit is checked and logged for: reachability, Seek USB enumeration
status, image.pgm health, pipeline type/version, pipeline restart count (24h rolling),
self-recovered-error count (24h rolling, new pipeline only), USB errors/resets, ethernet
link UP/DOWN count, CPU load/temp, calibration status, and - when something's wrong - a raw
`dmesg` snapshot for root-cause evidence.

## Metrics used to prove/disprove the goal

1. **Reachable %** per checkpoint
2. **Seek Enumeration failure rate and time-to-first-failure**
3. Whether a failure is **transient** (self-recovers) or **permanent** (never recovers for
   the rest of the run)
4. **Pipeline restart count** and **self-recovered-error count** - the new pipeline's
   designed self-healing behavior (absorbs transient USB errors as warnings instead of
   exiting - see `CHANGELOG.md`) has no equivalent on the old pipeline, so this is a direct
   test of whether that design change actually reduces real-world restarts
5. USB reset/error counts, CPU load overhead per pipeline

## Results to date

**Weekend test (2026-08-14/17), all 4 units on the old pipeline** (2 regular-OS PT units,
2 RamOS units): all 4 lost Seek USB around the same time, independent of OS/pipeline -
pointed at a shared bench/power cause rather than a per-camera or per-pipeline issue. This
run could not compare pipelines (nothing ran new), so RamOS was retired and swapped for a
second new-pipeline unit for the current matched-pair design.

**Overnight run (2026-08-20 18:19 - 2026-08-21 09:00), 2 old / 2 new matched pairs**:
2 of 4 units (PT2 - old, PT1NEW - new) developed a Seek USB enumeration failure that never
recovered for the rest of the run. The other 2 (PT1 - old, PT2NEW - new) had zero. Because
the failure hit one old and one new unit - not consistently either pipeline - this run does
not show a clear pipeline-driven pattern for the *enumeration* failure specifically. The
actual kernel evidence at the failure point (repeated USB descriptor-read timeouts, followed
by a kernel-level port power-cycle attempt that also failed) points to a hardware/power-level
cause below where either pipeline can influence it.

**What the new pipeline *did* show a real, measurable advantage on**: on the restart-test
pair, once a systemd rate-limiting bug in the test itself was fixed (`StartLimitBurst` was
silently blocking the test's own restart calls after 50/hour), PT2NEW ran the full 874-cycle
restart loop with USB Resets = 0 the entire time, vs. PT2 (old) accumulating hundreds. This
matches the documented v3 design change: absorbing transient USB errors as warnings instead
of exiting.

**Live reseat test on PT2 (2026-08-21, current repeatability run)**: with the Pi/hub left powered the
entire time (no reboot, no power-cycle), unplugging just the Seek camera's own USB cable for ~15
seconds and replugging it recovered enumeration immediately (`lsusb` went from no Seek device to
`289d:0011` present). This argues against the shared-power-rail theory, not for it - nothing about the
power source changed, only the connector was reseated, and the kernel's own automatic port-level power
cycle (dmesg evidence above) had already failed to fix it the same way. **However, PT2 failed again
later in the same run**, with the connector untouched - so this isn't a durable one-time fix. Points
toward an intermittent condition (marginal contact reopening under vibration/thermal cycling, or an
intermittent power sag under load) rather than a simple bad-seating event or a purely static power-rail
problem.

## Current working theory

The Seek enumeration hard-failures are most likely a hardware/power issue, not a
pipeline-software issue - consistent with the earlier weekend finding of the same pattern
across independent old-pipeline-only units. Testing this directly: swapping the 2 affected
units' PoE splitters for a higher-wattage model (same fix that resolved unrelated eth0
flapping on 2 other cameras) and re-running.

## Next steps

1. **Repeatability run (today, unchanged hardware/plan)** - confirm the enumeration failure
   reproduces before introducing the splitter as a new variable.
2. **Splitter swap test (separate, explicitly labeled run)** - once repeatability is
   documented, re-run the same 2 units with the higher-wattage splitter to test whether it
   resolves the enumeration failure.
3. **Automated trend reporting** (done, iterated on this week) - each run now auto-generates
   a spreadsheet + HTML trend report instead of requiring manual review of raw logs.
