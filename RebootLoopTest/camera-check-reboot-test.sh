#!/bin/bash
# camera-check-reboot-test.sh - forked from camera-check-v2.sh for the reboot/restart
# loop test. Two differences from the routine health check:
#   1. No "Recovery" section - never calls restart_pipeline(). This test needs to
#      observe natural post-reboot/post-restart behavior, not have it masked by
#      an automatic fix.
#   2. dmesg counts are NOT boot-noise-filtered - the first 60s of boot is exactly
#      the window this test cares about (that's where the USB reset/enumeration
#      activity happens), unlike the routine check which deliberately ignores it.
# Also adds an explicit "did the Seek camera completely fail to enumerate" field,
# separate from the general USB error count, and RAM/overlay stats for RamOS units.

RAMDISK="/usr/local/bin/camera/ramdisk/image.pgm"
STALE_SECS=60
MIN_BYTES=1000

HOST=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
UPTIME_SEC=$(cut -d. -f1 /proc/uptime 2>/dev/null)
[ -z "$UPTIME_SEC" ] && UPTIME_SEC=""

# -- Network ping (gateway) -------------------------------------
GW=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
if [ -n "$GW" ]; then
    PING_OUT=$(ping -c 1 -W 2 "$GW" 2>/dev/null)
    if echo "$PING_OUT" | grep -q " 0% packet loss"; then
        RTT=$(echo "$PING_OUT" | awk -F'/' '/rtt/{printf "%.1fms", $5}')
        NETWORK_DESC="OK - gateway $GW reachable (${RTT})"
    else
        NETWORK_DESC="DEGRADED - gateway $GW unreachable"
    fi
else
    NETWORK_DESC="FAILED - no default gateway found"
fi

CAM_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
MAC_ADDR=$(cat "/sys/class/net/${IFACE:-eth0}/address" 2>/dev/null)
[ -z "$MAC_ADDR" ] && MAC_ADDR="unknown"

find_worker_pid() {
    ps -eo pid,cmd 2>/dev/null | grep "$1" | grep -v "\.sh" | grep -v grep | awk '{print $1}' | head -1
}

# -- Pipeline type/version ---------------------------------------
PIPELINE_RUNNING=0
if systemctl is-active --quiet seekcamera-gstreamer 2>/dev/null; then
    PIPELINE_TYPE="new"
    PIPELINE_RUNNING=1
    # NRestarts resets to 0 on every manual stop/start or reboot, so it's not
    # a useful trend - count actual restart events from journalctl over a
    # fixed trailing window instead (same approach as camera-check-v2.sh).
    #
    # journalctl double-logs every line this service emits: openlog() sets
    # LOG_PERROR because -c (console) is required under systemd, so each
    # syslog() call is captured twice - once via /dev/log, once via stderr
    # capture. A naive grep -c here silently counts everything 2x. Confirmed
    # live on sv-206 2026-08-19/20 (raw "camera error:" count 24 vs true 12;
    # same 2x pattern on "exiting (code"). Anchoring on the doubled
    # "gstreamer[PID]: seekcamera-gstreamer[PID]:" prefix - which only the
    # real, non-duplicate capture path produces - gets the true count.
    RESTARTS=$(journalctl -u seekcamera-gstreamer --since "-24 hours" 2>/dev/null | grep -cE "gstreamer\[[0-9]+\]: seekcamera-gstreamer\[[0-9]+\]: seekcamera-gstreamer starting:")
    # Self-recovered errors: the SDK logs "camera error: ..." and keeps
    # running ("watchdog will handle it if frames actually stop") - this is
    # NOT a restart, it's the new pipeline absorbing a transient USB/comms
    # hiccup on its own. Same doubled-prefix dedup as RESTARTS above.
    SELF_RECOVERED=$(journalctl -u seekcamera-gstreamer --since "-24 hours" 2>/dev/null | grep -cE "gstreamer\[[0-9]+\]: seekcamera-gstreamer\[[0-9]+\]: camera error:")
elif pgrep -f "rtsp-seek-server" >/dev/null 2>&1; then
    PIPELINE_TYPE="old"
    PIPELINE_RUNNING=1
else
    PIPELINE_TYPE="old"
fi
if [ "$PIPELINE_TYPE" = "old" ]; then
    PIPELINE_RESTARTS=""
    SELF_RECOVERED_ERRORS="n/a (old pipeline)"
else
    PIPELINE_RESTARTS="$RESTARTS"
    SELF_RECOVERED_ERRORS="$SELF_RECOVERED"
fi

# -- CPU usage: total system + pipeline process, delta-sampled over ~1s -
# same technique camera-check-v2.sh uses. Directly relevant to this test:
# tonight's sv-156/sv-129 investigation found a livelocked process burning
# CPU while producing no output - the routine check catches that via this
# field, but this test's script had zero CPU visibility until now.
if [ "$PIPELINE_TYPE" = "new" ]; then
    PIPELINE_PID=$(systemctl show seekcamera-gstreamer --property=MainPID --value 2>/dev/null)
else
    PIPELINE_PID=$(find_worker_pid "rtsp-seek-server")
fi

read_cpu_stat() { awk '/^cpu / { print $2,$3,$4,$5,$6,$7,$8 }' /proc/stat; }
read_proc_ticks() {
    if [ -n "$1" ] && [ "$1" -gt 0 ] 2>/dev/null && [ -r "/proc/$1/stat" ]; then
        awk '{ print $14+$15 }' "/proc/$1/stat"
    else
        echo 0
    fi
}

set -- $(read_cpu_stat)
U1=$1; N1=$2; S1=$3; I1=$4; W1=$5; H1=$6; SI1=$7
TOTAL_1=$((U1+N1+S1+I1+W1+H1+SI1))
IDLE_1=$((I1+W1))
PIPE_T1=$(read_proc_ticks "$PIPELINE_PID")

sleep 1

set -- $(read_cpu_stat)
U2=$1; N2=$2; S2=$3; I2=$4; W2=$5; H2=$6; SI2=$7
TOTAL_2=$((U2+N2+S2+I2+W2+H2+SI2))
IDLE_2=$((I2+W2))
PIPE_T2=$(read_proc_ticks "$PIPELINE_PID")

CPU_DELTA=$((TOTAL_2 - TOTAL_1))
IDLE_DELTA=$((IDLE_2 - IDLE_1))
PIPE_DELTA=$((PIPE_T2 - PIPE_T1))

if [ "$CPU_DELTA" -gt 0 ]; then
    TOTAL_CPU_PCT=$(awk "BEGIN { printf \"%.2f\", (1 - $IDLE_DELTA/$CPU_DELTA)*100 }")
    PIPELINE_CPU_PCT=$(awk "BEGIN { v=$PIPE_DELTA/$CPU_DELTA*100; printf \"%.2f\", (v<0?0:v) }")
else
    TOTAL_CPU_PCT=""
    PIPELINE_CPU_PCT=""
fi

SDK_VERSION=$(dpkg -l 2>/dev/null | awk 'tolower($2) ~ /seekthermal-sdk/{print $3; exit}')
[ -z "$SDK_VERSION" ] && SDK_VERSION="unknown"
LINKED_VERSION=$(readlink /usr/lib/libseekcamera.so 2>/dev/null | sed -n 's#.*libseekcamera\.so\.##p')
if [ -n "$LINKED_VERSION" ]; then
    SDK_DISPLAY="linked=$LINKED_VERSION (dpkg=$SDK_VERSION)"
else
    SDK_DISPLAY="$SDK_VERSION"
fi
if [ "$PIPELINE_TYPE" = "old" ]; then
    PIPELINE_VERSION="$SDK_DISPLAY"
else
    BIN_VER=$(journalctl -u seekcamera-gstreamer 2>/dev/null | grep "starting: version=" | tail -1 | sed -n 's/.*version=\([^ ]*\).*/\1/p')
    [ -z "$BIN_VER" ] && BIN_VER="unknown"
    PIPELINE_VERSION="$SDK_DISPLAY $BIN_VER"
fi

# -- Calibration status (new pipeline only) ------------------------
# Same logic as camera-check-v2.sh - see that file's comment for the
# slope=0 BROKEN-vs-uncalibrated distinction and the journalctl -n 3000
# bounding rationale. Directly relevant to Test 2 (pipeline restart loop):
# calibration is only re-read at pipeline start, so this column shows
# whether each restart cycle actually picked up the current DB value.
#
# Scoped to the CURRENT running PID via MainPID, matching an exact
# ": calibration: " substring - not just "most recent match anywhere in the
# journal" / "contains calibrat". Confirmed live on PT1NEW/PT2NEW
# (2026-08-20) that the broader match false-positives on the pipeline's own
# "starting: ... pipeline=\"queue ! calibration ! ...\"" line (same word,
# different meaning - GStreamer element name, not a calibration.c log line),
# and that an unscoped tail-1 can return a PREVIOUS process's "loaded" line
# even when the CURRENT process never logged one (gst_calibration_start()
# doesn't always complete before the next restart cycle).
if [ "$PIPELINE_TYPE" = "new" ]; then
    CAL_PID=$(systemctl show seekcamera-gstreamer --property=MainPID --value 2>/dev/null)
    if [ -z "$CAL_PID" ] || [ "$CAL_PID" = "0" ]; then
        CAL_LINE=""
    else
        CAL_LINE=$(journalctl -u seekcamera-gstreamer -n 3000 --no-pager 2>/dev/null | grep -F "[$CAL_PID]:" | grep -F ": calibration: " | tail -1)
    fi
    if [ -z "$CAL_LINE" ]; then
        CALIBRATION="UNKNOWN - current process (PID ${CAL_PID:-?}) has not logged a calibration status"
    else
        CAL_SLOPE=$(echo "$CAL_LINE" | sed -n 's/.*slope=\([0-9.-]*\).*/\1/p')
        if [ -n "$CAL_SLOPE" ]; then
            CAL_OFFSET=$(echo "$CAL_LINE" | sed -n 's/.*offset=\([0-9.-]*\).*/\1/p')
            if awk -v s="$CAL_SLOPE" 'BEGIN{exit !(s==0)}'; then
                CALIBRATION="BROKEN - active but slope=0 (forces reading to 0.0C), offset=$CAL_OFFSET"
            else
                CALIBRATION="ACTIVE - slope=$CAL_SLOPE offset=$CAL_OFFSET"
            fi
        else
            CALIBRATION="UNCALIBRATED - $(echo "$CAL_LINE" | sed -n 's/.*\]: //p')"
        fi
    fi
else
    CALIBRATION="n/a (old pipeline)"
fi

# -- USB (Seek module) - live snapshot, not just dmesg history --
USB_LINE=$(lsusb 2>/dev/null | grep "289d")
if [ -n "$USB_LINE" ]; then
    USB_DESC="PRESENT - $USB_LINE"
    USB_OK=1
else
    USB_DESC="NOT FOUND"
    USB_OK=0
fi

# -- image.pgm ------------------------------------------------
IMAGE_OK=0
if [ "$PIPELINE_TYPE" = "new" ]; then
    if [ "$PIPELINE_RUNNING" -eq 1 ]; then
        IMAGE_DESC="n/a (gstreamer service active)"
        IMAGE_OK=1
    else
        IMAGE_DESC="n/a (gstreamer service not running)"
    fi
elif [ ! -f "$RAMDISK" ]; then
    IMAGE_DESC="MISSING"
elif [ "$(stat -c %s "$RAMDISK" 2>/dev/null || echo 0)" -lt "$MIN_BYTES" ]; then
    IMAGE_DESC="EMPTY (header only - pipeline not writing frames)"
else
    size=$(stat -c %s "$RAMDISK" 2>/dev/null)
    age=$(( $(date +%s) - $(stat -c %Y "$RAMDISK") ))
    if [ "$age" -gt "$STALE_SECS" ]; then
        IMAGE_DESC="STALE (last updated ${age}s ago)"
    else
        IMAGE_DESC="VALID (${size} bytes, updated ${age}s ago)"
        IMAGE_OK=1
    fi
fi
IMAGE_SIZE=$(stat -c %s "$RAMDISK" 2>/dev/null || echo 0)
IMAGE_AGE=$(( $(date +%s) - $(stat -c %Y "$RAMDISK" 2>/dev/null || date +%s) ))

# -- Ports ----------------------------------------------------
port_status() { ss -tlnp 2>/dev/null | grep -q ":$1" && echo "UP" || echo "DOWN"; }
PORT_IMGSERV=$(port_status 2105)
PORT_RTSP_8554=$(port_status 8554)

# -- Thermal ----------------------------------------------------
TEMP_C=$(vcgencmd measure_temp 2>/dev/null | sed -n 's/temp=\([0-9.]*\).*/\1/p')
THROTTLED=$(vcgencmd get_throttled 2>/dev/null | sed -n 's/throttled=\(0x[0-9a-fA-F]*\)/\1/p')
[ -z "$THROTTLED" ] && THROTTLED="0x0"

# -- dmesg counts - UNFILTERED (no 60s boot-noise exclusion, unlike the routine
# health check) since the boot window is exactly what this test observes --
dmesg_count_unfiltered() {
    dmesg 2>/dev/null | tail -n 2000 | awk -v pat="$1" 'tolower($0) ~ pat { c++ } END { print c+0 }'
}
USB_ERRORS=$(dmesg_count_unfiltered "usb.*error|cannot enumerate|device not accepting|usbdevfs_control failed|did not claim interface|usb disconnect|attempt power cycle|unable to enumerate")
USB_RESETS=$(dmesg_count_unfiltered "reset high-speed usb")
ETH_FLAP_COUNT=$(dmesg_count_unfiltered "link is down")

# -- Explicit "did the Seek camera completely fail to enumerate" field --
# Separate from the general USB_ERRORS count above - this specifically looks for
# the one terminal line the kernel logs when it gives up entirely on a USB port,
# after exhausting its own retry attempts. Distinct from transient resets/retries
# that go on to succeed.
ENUM_FAIL_LINE=$(dmesg 2>/dev/null | grep -i "unable to enumerate USB device" | tail -1)
if [ -n "$ENUM_FAIL_LINE" ]; then
    SEEK_ENUMERATION="FAILED - unable to enumerate USB device"
    ENUM_FAIL_TIME_SEC=$(echo "$ENUM_FAIL_LINE" | sed -n 's/^\[[ \t]*\([0-9.]*\)\].*/\1/p')
else
    SEEK_ENUMERATION="OK"
    ENUM_FAIL_TIME_SEC=""
fi

# -- RAM / overlay stats - only meaningful on RamOS units, harmless elsewhere --
MEM_LINE=$(free -h 2>/dev/null | awk '/^Mem:/{print $2","$3","$4","$6","$7}')
OVERLAY_ACTIVE=$(mount 2>/dev/null | grep -q "^overlay on / type overlay" && echo "YES" || echo "NO")
OVERLAY_USAGE=$(df -h 2>/dev/null | awk '/ \/$/{print $2","$3","$4","$5}')

# -- Final status ---------------------------------------------------
# Same additive-issues approach as camera-check-v2.sh (a camera can have more
# than one of these true at once), but no "after restart attempt" wording on
# the pipeline-down case - unlike the routine check, this script never calls
# restart_pipeline() itself (see header comment), so there's no restart to
# reference here; the reboot/restart cycle is driven externally by
# reboot_loop_test.py.
USB_UNSTABLE_THRESHOLD=5
ISSUES=()

if [ "$USB_OK" -eq 0 ]; then
    ISSUES+=("Seek not detected")
fi
if [ "$USB_RESETS" -ge "$USB_UNSTABLE_THRESHOLD" ] || [ "$USB_ERRORS" -ge "$USB_UNSTABLE_THRESHOLD" ]; then
    ISSUES+=("USB UNSTABLE - $USB_RESETS resets, $USB_ERRORS errors in dmesg")
fi
if [ "$USB_OK" -eq 1 ] && [ "$IMAGE_OK" -eq 0 ]; then
    ISSUES+=("PIPELINE DOWN - image $IMAGE_DESC")
fi
if [ "$ETH_FLAP_COUNT" -gt 0 ]; then
    ISSUES+=("eth0 flapping ($ETH_FLAP_COUNT events)")
fi

STATUS=$(printf '; %s' "${ISSUES[@]}")
STATUS="${STATUS#; }"
[ -z "$STATUS" ] && STATUS="PIPELINE HEALTHY"

# -- Raw dmesg tail - only captured when something's actually wrong -------
# 20 lines unconditionally proved too thin to be useful (a busy USB reset
# loop produces a new pair of lines every ~10s, so 20 lines barely covers
# one checkpoint's own cycle length) and bloated every row of the log
# whether anything happened or not. Capturing more, but only on trouble,
# gives a real forensic snapshot right when it matters instead.
if [ "$STATUS" = "PIPELINE HEALTHY" ]; then
    DMESG_TAIL=""
else
    DMESG_TAIL=$(dmesg -T 2>/dev/null | tail -n 100 | tr '\n' '|')
fi

# -- Structured report (KEY=VALUE, one per line) -------------------
echo "HOST=$HOST"
echo "TIMESTAMP=$TIMESTAMP"
echo "CAM_IP=$CAM_IP"
echo "MAC_ADDR=$MAC_ADDR"
echo "UPTIME_SEC=$UPTIME_SEC"
echo "NETWORK=$NETWORK_DESC"
echo "PIPELINE_TYPE=$PIPELINE_TYPE"
echo "PIPELINE_VERSION=$PIPELINE_VERSION"
echo "PIPELINE_RESTARTS=$PIPELINE_RESTARTS"
echo "SELF_RECOVERED_ERRORS=$SELF_RECOVERED_ERRORS"
echo "TOTAL_CPU_PCT=$TOTAL_CPU_PCT"
echo "PIPELINE_CPU_PCT=$PIPELINE_CPU_PCT"
echo "CALIBRATION=$CALIBRATION"
echo "USB=$USB_DESC"
echo "IMAGE_PGM=$IMAGE_DESC"
echo "IMAGE_SIZE=$IMAGE_SIZE"
echo "IMAGE_AGE_SEC=$IMAGE_AGE"
echo "IMAGE_OK=$IMAGE_OK"
echo "PORT_IMGSERV=$PORT_IMGSERV"
echo "PORT_RTSP_8554=$PORT_RTSP_8554"
echo "TEMP_C=$TEMP_C"
echo "THROTTLED=$THROTTLED"
echo "USB_ERRORS=$USB_ERRORS"
echo "USB_RESETS=$USB_RESETS"
echo "ETH_FLAP_COUNT=$ETH_FLAP_COUNT"
echo "SEEK_ENUMERATION=$SEEK_ENUMERATION"
echo "ENUM_FAIL_TIME_SEC=$ENUM_FAIL_TIME_SEC"
echo "MEM_LINE=$MEM_LINE"
echo "OVERLAY_ACTIVE=$OVERLAY_ACTIVE"
echo "OVERLAY_USAGE=$OVERLAY_USAGE"
echo "STATUS=$STATUS"
echo "DMESG_TAIL=$DMESG_TAIL"
