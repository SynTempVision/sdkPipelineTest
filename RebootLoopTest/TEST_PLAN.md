# New vs. Old Pipeline Test Plan

## Goal

Determine whether the new SDK pipeline (`seekcamera-gstreamer`) is better,
the same, or worse than the old pipeline (`rtsp-seek-server`).

## Alternate Goal:
Does the the new pipeline delay/prolong the onset of the hardware failure

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



