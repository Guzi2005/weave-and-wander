@echo off
setlocal
cd /d "%~dp0"
set "GODOT_EXE=D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT_EXE%" (
    set "GODOT_EXE=D:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe"
)
if not exist "%GODOT_EXE%" (
    set "GODOT_EXE=D:\Godot\Godot_v4.3-stable_mono_win64\Godot_v4.3-stable_mono_win64.exe"
)
start "" "%GODOT_EXE%" --path "%~dp0." res://scenes/garment_lab.tscn --windowed
