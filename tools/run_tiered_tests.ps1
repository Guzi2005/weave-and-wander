param(
    [ValidateSet("Tier1", "Tier2", "Tier3", "All")]
    [string]$Tier = "Tier1",
    [string]$GodotExe = "D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$ProjectPath = Split-Path -Parent $PSScriptRoot

$Tier1Tests = @(
    "tests/pleated_skirt_test.gd",
    "tests/wrapped_fabric_test.gd",
    "tests/material_package_test.gd",
    "tests/parametric_flower_test.gd",
    "tests/parametric_adornments_test.gd"
)

$Tier2Tests = @(
    "tests/workshop_architecture_and_audio_test.gd",
    "tests/material_handling_test.gd",
    "tests/dye_flow_test.gd",
    "tests/loom_production_test.gd",
    "tests/inventory_flow_test.gd"
)

$Tier3Tests = @(
    "tests/workbench_test.gd",
    "tests/street_glass_capture.gd"
)

$SelectedTests = switch ($Tier) {
    "Tier1" { $Tier1Tests }
    "Tier2" { $Tier2Tests }
    "Tier3" { $Tier3Tests }
    "All"   { $Tier1Tests + $Tier2Tests + $Tier3Tests }
}

Write-Host "=== Running 《针脚与远方》 (Weave&Wander) Automated Regression Suite [$Tier] ===" -ForegroundColor Cyan
$Failed = @()
foreach ($TestScript in $SelectedTests) {
    Write-Host "-> Running $TestScript ..." -ForegroundColor Yellow
    & $GodotExe --headless --path $ProjectPath --script $TestScript
    if ($LASTEXITCODE -ne 0) {
        $Failed += $TestScript
        Write-Host "   [FAIL] $TestScript (exit code $LASTEXITCODE)" -ForegroundColor Red
    } else {
        Write-Host "   [PASS] $TestScript" -ForegroundColor Green
    }
}

if ($Failed.Count -gt 0) {
    Write-Host "=== Regression Suite [$Tier] FAILED ($($Failed.Count) failed): $($Failed -join ', ') ===" -ForegroundColor Red
    exit 1
}
Write-Host "=== Regression Suite [$Tier] PASSED ($($SelectedTests.Count) suites) ===" -ForegroundColor Green
exit 0
