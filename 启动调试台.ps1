param(
    [string]$GodotPath = "D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    $candidates = @(
        "D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe",
        "D:\Godot\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64.exe"
    )
    $GodotPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

$launchArguments = '--path "{0}" res://scenes/garment_lab.tscn --windowed' -f $projectRoot
Start-Process -FilePath $GodotPath -WorkingDirectory $projectRoot -ArgumentList $launchArguments
