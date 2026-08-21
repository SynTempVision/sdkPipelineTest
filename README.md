# sdkPipelineTest

Test suites for stress-testing the Seek Thermal SDK camera pipeline (old `rtsp-seek-server`
vs new `seekcamera-gstreamer`) under reboot/restart conditions, comparing resilience and
recovery behavior between pipeline versions.

## Requirements

```
pip install paramiko openpyxl
```

## RebootLoopTest

Drives a fixed-cadence reboot **or** pipeline-restart loop against a camera and logs a
snapshot of its state every cycle - built to compare an old-pipeline unit against a
new-pipeline unit under the same stress pattern.

- **`reboot_loop_test.py`** - the test driver. Two modes via `--action`:
  - `reboot` (2-minute cycle): `sudo reboot`, wait, SSH back in, check, log, repeat.
  - `restart` (60-second cycle): restart the pipeline (`pipeline_restart.sh` for old,
    `systemctl restart seekcamera-gstreamer` + `reset-failed` for new, to avoid systemd's
    `StartLimitBurst` rate-limiting a test that deliberately restarts every cycle), check,
    log, repeat.

  ```bash
  python reboot_loop_test.py --ip 172.17.103.5 --password <pw> --unit "PT1" \
      --action reboot --pipeline old --duration-min 60
  ```

  Stop early any time with **Ctrl+C** (not window-close/force-kill) - that's caught as a
  clean stop and still generates the run's report; closing the window skips it.

- **`camera-check-reboot-test.sh`** - pushed to the camera fresh each cycle over SFTP and
  run remotely. Reports Seek USB enumeration, image.pgm health, pipeline type/version,
  restart counts, calibration status, CPU/USB/network stats, and a raw `dmesg` tail when
  something's wrong.

- **`run_reboot_test.ps1`** - launches all 4 standard units (PT1/PT1NEW old-pipeline vs
  new-pipeline reboot pair, PT2/PT2NEW old vs new restart pair) at once, each in its own
  window:

  ```powershell
  .\run_reboot_test.ps1 -DurationMin 60
  ```

### Output

- `logs/RebootLoopTest_<unit>.xlsx` - master log, all runs for that unit appended together
  (a `Run ID` column disambiguates cycles between runs).
- `reports/<unit>_<run-id>/` - one folder per run, generated automatically when a run ends
  (normally or via Ctrl+C):
  - `<unit>_<run-id>.xlsx` - that run's rows only.
  - `trend_report.html` - dependency-free (no external JS/CDN, just inline SVG), meant to
    be **opened as a local file**, not viewed through GitHub's file browser (which only
    shows HTML source, never renders it). Includes reachability/Seek-enumeration/image.pgm
    status strips with hover tooltips, numeric trend charts, a full summary (blip-aware -
    a missed checkpoint or a check-timing misread isn't counted as a real failure), a
    Status breakdown, and - when a real Seek Enumeration failure occurred - a Findings
    section with the actual `dmesg` evidence from the first failure.

- **`WEEKEND_TEST_FINDINGS.md`** - writeup from an earlier weekend-long run where all 4
  units lost Seek USB, pointing at a shared bench/power cause rather than independent
  per-camera or per-OS failures.
