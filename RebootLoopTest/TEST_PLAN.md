# New vs. Old Pipeline Test Plan

## Purpsoe for this test: 
To find The cameras at LB and HyCO4 have been experiencing IR Video Pipeline Failures. These failures include a frozen video pipeline and seek cameras not being able to enumerate. Frozen video pipeline can occur during boot and or during runtime. 


## Goal: 
Determine whether the new SDK pipeline (`seekcamera-gstreamer`) is better, the same, or worse than the old pipeline (`rtsp-seek-server`). And furthermore if none of the pipelines can solve the seek enumeration problem can the new one at least have fewer and or delay the seek enumeration hardware failure. Lastly, how can we solve the video pipeline errors. Side Note: i am not sure that wither of the pipelines can stop the Seek camera from not enumerating - This might be a Seek issue.

### Differences between the Old and New Pipeline:
   - OLD
      - uses the sdk 4.1 version
      - 
   - NEW
      - uses the sdk 4.4 version
      - 

## Test 0 Design:
Steady-state endurance.** Leave each pipeline running normally, with no deliberate reboot/restart stress at all, to catch slow-building problems that a constantly-restarting stress loop would mask by resetting state every cycle.

| Unit/Test# | Pipeline | Logging Cycle 
|---|---|---|---|
| PT0 | old (`rtsp-seek-server`) | 5 min | 
| PT0NEW | new (`seekcamera-gstreamer`) | 5 min |

### Instruments that are logged on a N cycle time
- Both pipelines:
   - Is the device reachable via ssh
   - Seek USB enumeration status (grep the kernel log and command that reads what devices are connected to the USB hub)
   - Network behavior: ethernet link UP/DOWN count (grep the kernal log)
   - CPU load / CPU Temp
   - kernal log snapshot that is replaced everytime it is updated so im not storing exxcessive amounts of data.
 
- New Pipeline:
   - Number of usb error warnings
   - Number of systemd resets on the pipeline
   - If calibration data loaded on pipeline start

- Old pipeline:
   - image.pgm health - Are the bytes valid and when the last write was ? 

## Things I am looking for:
1. Does it self-recover from USB errors the old pipeline can't?
2. Does the old/new pipeline fail, what is causing the failure and how can that be eliminated ?
3. Any difference in Seek enumeration failures between pipelines?
4. Any other faults/bugs, in either pipeline

Prediction: 
- if the new pipeline is better, it should show fewer/delayed Seek enumeration failures.

- Next Steps:
   - Get test planned reviewed and Approved
   - Build a website that displays the static information about each test device and the current status of test device during a test run.

## Future Test 1 Design:
Two stress conditions, each run on one old-pipeline unit and one new-pipeline unit in parallel:

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
- All units are burned with the same baseline OS image. 

### Instruments that are logged on a N cycle time
Every cycle, each unit is checked and logged for: reachability, Seek USB enumeration
status, image.pgm health, pipeline type/version, pipeline restart count,
self-recovered-error count (24h, new pipeline only), USB errors/resets, ethernet
link UP/DOWN count, CPU load/temp, calibration status, and - when something's wrong - a raw
`dmesg` snapshot for root-cause evidence.

