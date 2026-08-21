# New vs. Old Pipeline Test Plan

### Purpose of this test: The cameras at LB and HyCO4 have been experiencing IR Video Pipeline Failures. These failures include a frozen video pipeline and seek cameras not being able to enumerate. Frozen video pipeline can occur during boot and or during runtime. 

### Goal: Determine whether the new SDK pipeline (`seekcamera-gstreamer`) is better, the same, or worse than the old pipeline (`rtsp-seek-server`). And furthermore if none of the pipelines can solve the seek enumeration problem can the new one at least delays the seek enumeration hardware failure.

Differences between the Old and New Pipeline:
   - OLD
      - uses the sdk 4.1 version
      - 
   - NEW
      - uses the sdk 4.4 version
      - 

### Instruments  

- Both pipelines:
   - Seek USB enumeration
   - Network behavior
   - Is the device reachable ?
   - CPU load / CPU Temp
   - kernal log snapshot

- New Pipeline:
   - Number of usb error warnings
   - Number of systemd resets on the pipeline 

- Old pipeline:
   - image.pgm health - Are the bytes valid and when the last write was ? 

## Things I am looking for:
1. Does the new pipeline restart less often under the same stress?
2. Does it self-recover from USB errors the old pipeline can't?
3. Any difference in Seek enumeration failures between pipelines?
4. Any other faults/bugs, in either pipeline, that show up under sustained stress?

This is directly testable: 
if the new pipeline is better, it should show fewer/deplayed Seek
enumeration failures.

## Test Design

**Option 1 - Matched pairs.** Two stress conditions, each run on one old-pipeline unit and
one new-pipeline unit in parallel:

| Unit | Pipeline | Stress action | Cycle 
|---|---|---|---|
| PT1 | old (`rtsp-seek-server`) | software reboot | 2 min | 
| PT1NEW | new (`seekcamera-gstreamer`) | software reboot | 2 min |
| PT2 | old (`rtsp-seek-server`) | pipeline restart | 60 sec |
| PT2NEW | new (`seekcamera-gstreamer`) | pipeline restart | 60 sec |

- All units have the same Power input
    - (PoE Splitter 5V 3.5A OR 12V 2A) because I have qty 4 of each.
    - STEAMO Model:GPOE208 Gigabit PoE Switch
    - The same ethernet cables
- All units have the same OS images
- All units will have a color camera and IR seek camera
    - The reboot kills the connection for the color camera streaming via VLC
       - I need to device if it is worth creating a script to reactive stream after reboot to have the same load on the cpu
     

**Option 2 - Steady-state endurance.** Leave each pipeline running normally, with no
deliberate reboot/restart stress at all, to catch slow-building problems that a constantly-restarting stress loop would mask by resetting state every cycle.

Every cycle, each unit is checked and logged for: reachability, Seek USB enumeration
status, image.pgm health, pipeline type/version, pipeline restart count,
self-recovered-error count (24h, new pipeline only), USB errors/resets, ethernet
link UP/DOWN count, CPU load/temp, calibration status, and - when something's wrong - a raw
`dmesg` snapshot for root-cause evidence.

- Next Steps:
   - Get test planned reviewed and Approved
   - Build a website that displays the static information about each test device and the current status of test device during a test run.


Notes: 
