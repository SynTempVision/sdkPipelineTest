# New vs. Old Pipeline Test Plan
rev3
8/21/26

## Purpose for this test: 
To find a solution for the cameras at LB and HyCO4 that have been experiencing IR Video Pipeline Failures. These failures include a frozen video pipeline and seek cameras not being able to enumerate. Frozen video pipeline can occur during boot and or during runtime. 


## Goal: 
Determine whether the new SDK pipeline (`seekcamera-gstreamer`) is better, the same, or worse than the old pipeline (`rtsp-seek-server`). And furthermore if none of the pipelines can solve the seek enumeration problem can the new one at least have fewer and or delay the seek enumeration hardware failure. Solve / Mitigate the video pipeline failures. 
Side Note: I am not sure that either of the pipelines can stop the Seek camera from enumeration failure - This might be a Seek issue.

### Differences between the Old and New Pipeline:
   - OLD Pipeline
      - created by KDK
      - uses the sdk 4.1 version
      - started via crontab job that run system_init.sh at boot
```
appsrc name=app0 format=time ! timecodestamper ! normfilter ! tee name=tp 
  tp. ! queue ! rtpgstpay name=pay0
  tp. ! queue ! multifilesink max-files=10 location="/usr/local/bin/camera/ramdisk/image%d"
```

```
Element: appsrc (name=app0, format=time)
Role: SDK-fed raw thermal frame source, with time-based timestamps
────────────────────────────────────────
Element: timecodestamper
Role: Adds precise timestamps to each buffer for synchronization
────────────────────────────────────────
Element: normfilter
Role: Custom normalization filter 
────────────────────────────────────────
Element: tee (name=tp)
Role: Splits the stream into two parallel branches — RTP streaming and
file save. GStreamer-native fan-out.
────────────────────────────────────────
Element: queue ! rtpgstpay (name=pay0)  [Branch 1]
Role: Payloads the stream for RTP streaming (needs an external sink like
udpsink to actually transmit it)
────────────────────────────────────────
Element: queue ! multifilesink (max-files=10, location="image%d")  [Branch 2]
Role: Saves frames to disk as a rotating buffer of up to 10 files
```

- rtsp-seek-server.sh: launched once at boot in crontab. Its `while` loop runs `usbreset` + relaunches every time the binary exits. Gaps: doesn't catch a hang (binary frozen, not exited), and can't self-heal if the wrapper process itself dies. Both measurable via `pgrep -f rtsp-seek-server.sh` (wrapper alive?) + process/CPU%/image.pgm-freshness (crashed vs hung vs livelocked vs healthy).

   - NEW pipeline
      - written by sophia and claude
      - uses the sdk 4.4 version
      - systemd service (seekcamera-gstreamer.service)
      - Has an internal watchdog: absorbs USB timeout errors as warnings and keeps running; only exits and restarts if image frames stop being produced. 

```
appsrc ! queue ! calibration ! pgmencode ! syntempsink
```

```
Element: appsrc
Role: SDK-fed raw thermal frame source 
────────────────────────────────────────
Element: queue
Role: Buffering/threading boundary between the SDK callback thread and
the rest of the pipeline
────────────────────────────────────────
Element: calibration
Role: Applies the per-camera calibration (slope/offset fromcamera_imager) — this is the custom element read once at pipeline start (gst_calibration_start())
────────────────────────────────────────
Element: pgmencode
Role: Encodes the calibrated frame into PGM format
────────────────────────────────────────
Element: syntempsink
Role: Custom sink — writes/serves the final output to SynTemp Vision on port 2105
```
     

## Test 0 Design:
Steady-state endurance.** Leave each pipeline running normally, with no deliberate reboot/restart stress at all, to catch slow-building problems that a constantly-restarting stress loop would mask by resetting state every cycle.

- 4 units total so that was there is replication in the setup. more details below:

| Unit/Test# | Pipeline | Type | Logging Cycle 
|---|---|---|---|
| PT0.1 | old (`rtsp-seek-server`) | Type A | 5 min | 
| PT0.1NEW | new (`seekcamera-gstreamer`) | Type B | 5 min |
| PT0.2 | old (`rtsp-seek-server`) | Type A | 5 min | 
| PT0.2NEW | new (`seekcamera-gstreamer`) | Type B | 5 min |

- All units have the same Power input
    - PoE Splitter (5V 3.5A) because I have qty 4 of each.
    - STEAMO Model:GPOE208 Gigabit PoE Switch
    - The same ethernet cables
- All units are burned with the same baseline OS image
    - changes are that TYPE B has the new pipeline ( binaries and services newSDK ) the old pipeline is there but not active

### Instruments that are logged on a N cycle time for N amount of days
- Both pipelines:
   - Is the device reachable via ssh
   - Seek USB enumeration status (grep the kernel log and command that reads what devices are connected to the USB hub)
   - Network behavior: ethernet link UP/DOWN count (grep the kernal log)
   - CPU load / CPU Temp / CPU Throttling
   - kernal log snapshot that is replaced everytime it is updated so im not storing exxcessive amounts of data.
 
- New Pipeline:
   - Number of USB error warnings
   - Number of systemd resets on the pipeline
   - If calibration data loaded on pipeline start

- Old pipeline:
   - image.pgm health - Are the bytes valid and when the last write was ? 

### Things I am looking for:
1. Does it self-recover from USB errors the old pipeline can't?
2. Does the old/new pipeline fail, what is causing the failure and how can that be eliminated ?
3. Any difference in Seek enumeration failures between pipelines?
4. Any other faults/bugs, in either pipeline

### Prediction: 
- if the new pipeline is better, it should show fewer/delayed Seek enumeration failures.

### Test Succession Criteria:
- The new pipeline has no lost seek enumeration or at least less than the old pipeline

### Next Steps:
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
- Both pipelines:
   - Is the device reachable via SSH
   - Seek USB enumeration status (grep the kernel log and command that reads what devices are connected to the USB hub)
   - Network behavior: ethernet link UP/DOWN count (grep the kernel log)
   - CPU load / CPU Temp / CPU Throttling
   - kernel log snapshot that is replaced every time it is updated so I'm not storing excessive amounts of data.
 
- New Pipeline:
   - Number of USB error warnings
   - Number of systemd resets on the pipeline
   - If calibration data loaded on pipeline start

- Old pipeline:
   - image.pgm health - Are the bytes valid and when the last write was?
