param(
    [string]$GodotPath = "D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe",
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    $candidates = @(
        "D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe",
        "C:\Program Files\Godot\Godot.exe",
        "C:\Program Files\Godot\Godot_v4.7.1-stable_win64.exe"
    )
    $GodotPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("找不到 Godot 4. 请用 -GodotPath 指定 Godot.exe。", "针脚与远方") | Out-Null
    exit 1
}

# The editor PID belongs to Godot's editor, not this short-lived launcher.
# Quote the project path because Start-Process joins ArgumentList on Windows.
$launchArguments = '--path "{0}" res://main.tscn --windowed' -f $projectRoot
if ($Verify) {
    $launchArguments += ' --log-file "' + (Join-Path $projectRoot 'captures/desktop_launch_test.log') + '" -- --smoke-test --test-window=1280x800'
    $gameProcess = Start-Process -FilePath $GodotPath -WorkingDirectory $projectRoot -ArgumentList $launchArguments -PassThru
    $gameProcess.WaitForExit()
    exit $gameProcess.ExitCode
}
Start-Process -FilePath $GodotPath -WorkingDirectory $projectRoot -ArgumentList $launchArguments
