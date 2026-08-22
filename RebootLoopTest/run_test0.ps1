# run_test0.ps1 - launches Test 0 (steady-state endurance, TEST_PLAN.md) on
# all 4 units: PT0.1/PT0.2 on the old pipeline, PT0.1NEW/PT0.2NEW on the new
# pipeline. Same physical hardware as PT1/PT1NEW/PT2/PT2NEW (Future Test 1),
# just repurposed here with action=none - a passive check every 5 minutes,
# no reboot/restart triggered at all, to catch slow-building problems a
# constantly-restarting stress loop would mask by resetting state every cycle.
#
# -DurationMin is optional - omit it to run fully open-ended (until you
# Ctrl+C each window), or pass an explicit duration (e.g. to target a
# specific end time) so an unattended multi-day run doesn't rely on someone
# catching all 4 windows manually. Ctrl+C only, not window-close/kill, or
# the run's report won't auto-generate.
#
# Usage:
#   .\run_test0.ps1                    # open-ended
#   .\run_test0.ps1 -DurationMin 4084   # stop after ~68 hours

param(
    [int]$DurationMin = 0
)

$ScriptDir = $PSScriptRoot
$Password = "password"
$DurationArg = if ($DurationMin -gt 0) { "--duration-min $DurationMin" } else { "" }

$Devices = @(
    @{ Ip = "172.17.103.43";  Unit = "PT0.1";    Pipeline = "old"; Log = "logs\RebootLoopTest_PT0.1.xlsx" },
    @{ Ip = "172.17.103.135"; Unit = "PT0.1NEW"; Pipeline = "new"; Log = "logs\RebootLoopTest_PT0.1NEW.xlsx" },
    @{ Ip = "172.17.103.31";  Unit = "PT0.2";    Pipeline = "old"; Log = "logs\RebootLoopTest_PT0.2.xlsx" },
    @{ Ip = "172.17.103.206"; Unit = "PT0.2NEW"; Pipeline = "new"; Log = "logs\RebootLoopTest_PT0.2NEW.xlsx" }
)

$LaunchDir = Join-Path $env:TEMP "reboot_loop_launchers"
New-Item -ItemType Directory -Force -Path $LaunchDir | Out-Null

foreach ($d in $Devices) {
    $logLeaf = Split-Path $d.Log -Leaf
    $launcherPath = Join-Path $LaunchDir ("launch_" + ($logLeaf -replace '\.xlsx$','') + ".ps1")
    @"
Set-Location '$ScriptDir'
python reboot_loop_test.py --ip $($d.Ip) --password $Password --unit "$($d.Unit)" --action none --pipeline $($d.Pipeline) --log $($d.Log) $DurationArg
"@ | Set-Content -Path $launcherPath -Encoding UTF8
    Start-Process powershell -ArgumentList @("-NoExit", "-File", $launcherPath)
}

Write-Host "Launched Test 0 (steady-state, 5-min cycle, no action) on PT0.1, PT0.1NEW, PT0.2, PT0.2NEW - open-ended, Ctrl+C each window when you want a run report."
