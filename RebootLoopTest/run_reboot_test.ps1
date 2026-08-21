# run_reboot_test.ps1 - launches all 4 reboot_loop_test.py runs (PT1, PT2 on
# the old pipeline; PT1NEW, PT2NEW on the new pipeline, formerly PTRamOS1/2
# before their RamOS storage was retired) at once, each in its own PowerShell
# window so you can watch each device's live cycle output separately.
# Defaults to a 60-minute run.
#
# Usage:
#   .\run_reboot_test.ps1                  # 60 min (default)
#   .\run_reboot_test.ps1 -DurationMin 120  # override duration

param(
    [int]$DurationMin = 60
)

$ScriptDir = $PSScriptRoot
$Password = "password"

$Devices = @(
    @{ Ip = "172.17.103.43";  Unit = "PT1";    Action = "reboot";  Pipeline = "old"; Log = "logs\RebootLoopTest_PT1.xlsx" },
    @{ Ip = "172.17.103.135"; Unit = "PT1NEW"; Action = "reboot";  Pipeline = "new"; Log = "logs\RebootLoopTest_PT1NEW.xlsx" },
    @{ Ip = "172.17.103.31";  Unit = "PT2";    Action = "restart"; Pipeline = "old"; Log = "logs\RebootLoopTest_PT2.xlsx" },
    @{ Ip = "172.17.103.206"; Unit = "PT2NEW"; Action = "restart"; Pipeline = "new"; Log = "logs\RebootLoopTest_PT2NEW.xlsx" }
)

$LaunchDir = Join-Path $env:TEMP "reboot_loop_launchers"
New-Item -ItemType Directory -Force -Path $LaunchDir | Out-Null

foreach ($d in $Devices) {
    $logLeaf = Split-Path $d.Log -Leaf
    $launcherPath = Join-Path $LaunchDir ("launch_" + ($logLeaf -replace '\.xlsx$','') + ".ps1")
    @"
Set-Location '$ScriptDir'
python reboot_loop_test.py --ip $($d.Ip) --password $Password --unit "$($d.Unit)" --action $($d.Action) --pipeline $($d.Pipeline) --duration-min $DurationMin --log $($d.Log)
"@ | Set-Content -Path $launcherPath -Encoding UTF8
    Start-Process powershell -ArgumentList @("-NoExit", "-File", $launcherPath)
}

Write-Host "Launched 4 test windows (PT1, PT1NEW, PT2, PT2NEW), duration $DurationMin min each."
